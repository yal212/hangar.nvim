---Run lifecycle: spawn headless agent jobs, parse their output stream,
---maintain the run registry, and persist it across nvim sessions.
---
---UI layers subscribe via `User HangarRunUpdate` autocmds (data = { id }).
local worktree = require("hangar.worktree")

local M = {}

---@class hangar.Run
---@field id string
---@field prompt string
---@field status "queued"|"running"|"done"|"failed"|"killed"|"merged"|"orphaned"
---@field adapter string
---@field permission_mode string
---@field model string|nil
---@field root string
---@field worktree string|nil nil while queued (created when the run starts)
---@field branch string|nil
---@field base string|nil
---@field started integer
---@field finished integer|nil
---@field exit_code integer|nil
---@field cost number|nil
---@field turns integer|nil
---@field session_id string|nil
---@field events table[]
---@field error string|nil
---@field stderr string|nil
---@field pid integer|nil
---@field result_is_error boolean|nil
---@field group string|nil best-of-n group id shared by sibling attempts
---@field attempt integer|nil 1-based attempt index within the group

---Registry: id -> run. Job handles live in `jobs` (not serializable).
M.runs = {}
local jobs = {}
local loaded = false

local state_dir_override ---tests point persistence at a scratch dir

function M._set_state_dir(dir)
  state_dir_override = dir
end

local function state_file()
  return (state_dir_override or vim.fn.stdpath("data")) .. "/hangar/runs.json"
end

local function notify_update(id)
  vim.api.nvim_exec_autocmds("User", { pattern = "HangarRunUpdate", data = { id = id } })
end

function M.save()
  local path = state_file()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.json.encode, M.runs)
  if ok then
    local f = io.open(path, "w")
    if f then
      f:write(encoded)
      f:close()
    end
  end
end

---Load persisted runs once per session. Runs that were live in a previous
---session can't be reattached, so they become "orphaned" (worktree, if any,
---is still reviewable/mergeable).
function M.load()
  if loaded then
    return
  end
  loaded = true
  local f = io.open(state_file(), "r")
  if not f then
    return
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return
  end
  for id, run in pairs(decoded) do
    if run.status == "running" then
      run.status = "orphaned"
    elseif run.status == "queued" then
      -- never auto-spawn agents on startup; the prompt is still visible
      run.status = "killed"
      run.error = "queued run never started (nvim exited)"
    end
    M.runs[id] = run
  end
end

---Runs for the given repo root, newest first.
---@return hangar.Run[]
function M.list(root)
  M.load()
  local out = {}
  for _, run in pairs(M.runs) do
    if run.root == root then
      out[#out + 1] = run
    end
  end
  table.sort(out, function(a, b)
    return a.started > b.started
  end)
  return out
end

function M.get(id)
  M.load()
  return M.runs[id]
end

local function short_id()
  local base = tostring(os.date("%H%M%S"))
  local id = base
  local n = 1
  while M.runs[id] do
    n = n + 1
    id = base .. "-" .. n
  end
  return id
end

---Apply one normalized adapter event to the run's state + transcript.
local function apply_event(run, ev)
  if ev.kind == "batch" then
    for _, sub in ipairs(ev.events) do
      apply_event(run, sub)
    end
    return
  end
  if ev.kind == "init" then
    run.model = ev.model or run.model
    run.session_id = ev.session_id
    return -- not a transcript entry
  end
  if ev.kind == "result" then
    if ev.partial then
      -- per-step stats (opencode): accumulate, no transcript entry
      run.cost = (run.cost or 0) + (ev.cost or 0)
      run.turns = (run.turns or 0) + 1
      return
    end
    run.cost = ev.cost
    run.turns = ev.turns
    run.result_is_error = ev.is_error
    if ev.is_error and ev.text then
      run.error = ev.text
    end
  end
  if ev.kind == "text" and ev.delta then
    -- streaming adapters (gemini) emit text in small deltas; coalesce
    local last = run.events[#run.events]
    if last and last.kind == "text" and last.delta then
      last.text = last.text .. ev.text
      return
    end
  end
  run.events[#run.events + 1] = ev
end

M._apply_event = apply_event -- exposed for tests

---Notify on a finished run, unless configured off or the dashboard already
---shows the change live.
local function notify_finish(run)
  local sink = require("hangar").config.notify
  if sink == false or (run.status ~= "done" and run.status ~= "failed") then
    return
  end
  local dashboard = package.loaded["hangar.ui.dashboard"]
  if dashboard and dashboard.is_open() then
    return
  end
  if type(sink) == "function" then
    sink(run)
    return
  end
  local secs = math.max(0, (run.finished or 0) - (run.started or 0))
  local msg = ("[hangar] %s %s in %02d:%02d"):format(run.id, run.status, math.floor(secs / 60), secs % 60)
  if run.cost then
    msg = msg .. (" ($%.2f)"):format(run.cost)
  end
  if run.status == "failed" and run.error then
    msg = msg .. ": " .. run.error:sub(1, 120)
  end
  vim.notify(msg, run.status == "done" and vim.log.levels.INFO or vim.log.levels.ERROR)
end

local promote_queued -- forward declaration; defined after start_run below

local function finish(run, code)
  run.exit_code = code
  run.finished = os.time()
  if run.status == "running" then
    if code == 0 and not run.result_is_error then
      run.status = "done"
      if worktree.is_dirty(run) then
        -- claude -p doesn't commit unless told; commit so the branch is mergeable
        local ok, err = pcall(worktree.commit_all, run, ("hangar: %s"):format(run.prompt:sub(1, 72)))
        if not ok then
          run.status = "failed"
          run.error = "auto-commit failed: " .. tostring(err)
        end
      end
    else
      run.status = "failed"
      run.error = run.error or ("exit code " .. code)
    end
  end
  jobs[run.id] = nil
  M.save()
  notify_update(run.id)
  notify_finish(run)
  promote_queued()
end

M._finish = finish -- exposed for tests

local function count_running()
  local n = 0
  for _, run in pairs(M.runs) do
    if run.status == "running" then
      n = n + 1
    end
  end
  return n
end

---@class hangar.SpawnOpts
---@field permission_mode "acceptEdits"|"bypassPermissions"
---@field model string|nil
---@field adapter string|nil adapter name, defaults to config.adapter
---@field group string|nil best-of-n group id (set by hangar.spawn for --n fleets)
---@field attempt integer|nil attempt index within the group

---Launch the agent process for a run whose worktree already exists, wiring
---stdout through the adapter's parser into the run's transcript.
---@param run hangar.Run
---@param adapter table
---@param cmd string[]
local function start_job(run, adapter, cmd)
  run.status = "running"
  run.started = os.time()
  local carry = "" -- partial stream-json line between stdout chunks
  local sysobj = vim.system(cmd, {
    cwd = run.worktree,
    text = true,
    stdout = function(_, data)
      if not data then
        return
      end
      carry = carry .. data
      local batch = {}
      while true do
        local nl = carry:find("\n", 1, true)
        if not nl then
          break
        end
        local line = carry:sub(1, nl - 1)
        carry = carry:sub(nl + 1)
        local ev = adapter.parse_line(line)
        if ev then
          batch[#batch + 1] = ev
        end
      end
      if #batch > 0 then
        vim.schedule(function()
          for _, ev in ipairs(batch) do
            apply_event(run, ev)
          end
          notify_update(run.id)
        end)
      end
    end,
    stderr = function(_, data)
      if data and vim.trim(data) ~= "" then
        run.stderr = ((run.stderr or "") .. data):sub(-2000)
      end
    end,
  }, function(res)
    vim.schedule(function()
      finish(run, res.code)
    end)
  end)
  jobs[run.id] = sysobj
  run.pid = sysobj.pid
end

---Create a run's worktree and start its agent process.
---@param run hangar.Run
---@return boolean ok
---@return string|nil err
local function start_run(run)
  local config = require("hangar").config
  local adapter = assert(require("hangar.adapters").get(run.adapter)) -- validated at spawn
  local overrides = config.adapters[run.adapter] or {}
  local cmd_override = overrides.cmd
  if run.adapter == "claude_code" and not cmd_override and config.claude_cmd ~= "claude" then
    cmd_override = config.claude_cmd
  end

  local ok, wt = pcall(worktree.create, run.root, run.id)
  if not ok then
    return false, tostring(wt)
  end
  run.worktree, run.branch, run.base = wt.path, wt.branch, wt.base

  local cmd = adapter.build_cmd({
    prompt = run.prompt,
    permission_mode = run.permission_mode,
    model = run.model,
    cmd = cmd_override,
    cwd = wt.path,
  })
  start_job(run, adapter, cmd)
  return true
end

---Start queued runs (oldest first) while there is capacity.
promote_queued = function()
  local cap = require("hangar").config.max_concurrent
  while true do
    if cap and count_running() >= cap then
      return
    end
    local next_run
    for _, run in pairs(M.runs) do
      if run.status == "queued" and (not next_run or run.started < next_run.started) then
        next_run = run
      end
    end
    if not next_run then
      return
    end
    local ok, err = start_run(next_run)
    if not ok then
      next_run.status = "failed"
      next_run.error = err
      next_run.finished = os.time()
    end
    M.save()
    notify_update(next_run.id)
  end
end

---Spawn an agent run in a fresh worktree. With config.max_concurrent set and
---no free slot, the run parks as "queued" and starts when one opens up.
---@param prompt string
---@param opts hangar.SpawnOpts
---@return hangar.Run|nil run
---@return string|nil err
function M.spawn(prompt, opts)
  M.load()
  local config = require("hangar").config
  local root, err = worktree.root()
  if not root then
    return nil, err
  end

  local adapter_name = opts.adapter or config.adapter
  local adapter, aerr = require("hangar.adapters").get(adapter_name)
  if not adapter then
    return nil, aerr
  end
  local unsupported = adapter.unsupported_modes and adapter.unsupported_modes[opts.permission_mode]
  if unsupported then
    return nil, unsupported
  end
  -- config.model stays claude-only; other adapters use their per-adapter override
  local overrides = config.adapters[adapter.name] or {}
  local default_model = adapter.name == "claude_code" and config.model or nil

  local id = short_id()
  ---@type hangar.Run
  local run = {
    id = id,
    prompt = prompt,
    status = "queued",
    adapter = adapter.name,
    permission_mode = opts.permission_mode,
    model = opts.model or overrides.model or default_model,
    root = root,
    started = os.time(), -- queue order; reset when the job actually starts
    events = {},
    group = opts.group,
    attempt = opts.attempt,
  }
  M.runs[id] = run

  if not (config.max_concurrent and count_running() >= config.max_concurrent) then
    local ok, serr = start_run(run)
    if not ok then
      M.runs[id] = nil
      return nil, serr
    end
  end
  M.save()
  notify_update(id)
  return run
end

---Kill a running job (SIGTERM) or drop a queued run from the queue.
---@return boolean ok
---@return string|nil err
function M.kill(id)
  local job = jobs[id]
  local run = M.runs[id]
  if not run then
    return false, "no such run: " .. tostring(id)
  end
  if run.status == "queued" then
    run.status = "killed"
    run.finished = os.time()
    M.save()
    notify_update(id)
    return true
  end
  if not job then
    return false, "run " .. id .. " is not running"
  end
  run.status = "killed"
  job:kill(15)
  return true
end

---Forget a run and delete its worktree + branch.
function M.discard(id)
  local run = M.runs[id]
  if not run then
    return false, "no such run: " .. tostring(id)
  end
  if run.status == "running" then
    return false, "run " .. id .. " is still running; kill it first"
  end
  worktree.remove(run)
  M.runs[id] = nil
  M.save()
  notify_update(id)
  return true
end

---Merge a finished run, then clean up its worktree + branch.
function M.merge(id, strategy)
  local run = M.runs[id]
  if not run then
    return false, "no such run: " .. tostring(id)
  end
  if run.status == "running" then
    return false, "run " .. id .. " is still running"
  end
  if run.status == "queued" then
    return false, "run " .. id .. " has not started yet"
  end
  local ok, err = worktree.merge(run, strategy or require("hangar").config.merge)
  if not ok then
    return false, err
  end
  worktree.remove(run)
  run.status = "merged"
  M.save()
  notify_update(id)
  return true
end

---Remove worktrees/branches of all non-running runs and drop them from the registry.
---@return integer count
function M.clean(root)
  local count = 0
  for id, run in pairs(M.runs) do
    if run.root == root and run.status ~= "running" then
      worktree.remove(run)
      M.runs[id] = nil
      count = count + 1
    end
  end
  M.save()
  notify_update(nil)
  return count
end

return M
