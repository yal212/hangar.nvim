---Run lifecycle: spawn headless agent jobs, parse their output stream,
---maintain the run registry, and persist it across nvim sessions.
---
---UI layers subscribe via `User HangarRunUpdate` autocmds (data = { id }).
local worktree = require("hangar.worktree")

local M = {}

---@class hangar.Run
---@field id string
---@field prompt string
---@field status "running"|"done"|"failed"|"killed"|"merged"|"orphaned"
---@field adapter string
---@field permission_mode string
---@field model string|nil
---@field root string
---@field worktree string
---@field branch string
---@field base string
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

---Registry: id -> run. Job handles live in `jobs` (not serializable).
M.runs = {}
local jobs = {}
local loaded = false

local function state_file()
  return vim.fn.stdpath("data") .. "/hangar/runs.json"
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
    run.cost = ev.cost
    run.turns = ev.turns
    run.result_is_error = ev.is_error
    if ev.is_error and ev.text then
      run.error = ev.text
    end
  end
  run.events[#run.events + 1] = ev
end

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
end

---@class hangar.SpawnOpts
---@field permission_mode "acceptEdits"|"bypassPermissions"
---@field model string|nil
---@field adapter string|nil adapter name, defaults to config.adapter

---Spawn an agent run in a fresh worktree.
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
  local overrides = config.adapters[adapter.name] or {}
  local cmd_override = overrides.cmd
  if adapter.name == "claude_code" and not cmd_override and config.claude_cmd ~= "claude" then
    cmd_override = config.claude_cmd
  end
  -- config.model stays claude-only; other adapters use their per-adapter override
  local default_model = adapter.name == "claude_code" and config.model or nil

  local id = short_id()
  local ok, wt = pcall(worktree.create, root, id)
  if not ok then
    return nil, tostring(wt)
  end

  local model = opts.model or overrides.model or default_model
  local cmd = adapter.build_cmd({
    prompt = prompt,
    permission_mode = opts.permission_mode,
    model = model,
    cmd = cmd_override,
  })

  ---@type hangar.Run
  local run = {
    id = id,
    prompt = prompt,
    status = "running",
    adapter = adapter.name,
    permission_mode = opts.permission_mode,
    model = model,
    root = root,
    worktree = wt.path,
    branch = wt.branch,
    base = wt.base,
    started = os.time(),
    events = {},
  }
  M.runs[id] = run

  local carry = "" -- partial stream-json line between stdout chunks
  local sysobj = vim.system(cmd, {
    cwd = wt.path,
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
          notify_update(id)
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

  jobs[id] = sysobj
  run.pid = sysobj.pid
  M.save()
  notify_update(id)
  return run
end

---Kill a running job (SIGTERM).
---@return boolean ok
---@return string|nil err
function M.kill(id)
  local job = jobs[id]
  local run = M.runs[id]
  if not run then
    return false, "no such run: " .. tostring(id)
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
