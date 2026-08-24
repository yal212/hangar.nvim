---hangar.nvim — run a fleet of coding agents in parallel git worktrees.
local M = {}

M.version = "0.1.0"

---@class hangar.Config
M.config = {
  ---Default permission mode for spawns without an explicit --yolo/--safe flag.
  ---nil (default) means every spawn must pass one; "yolo" or "safe" opt in.
  default_permission = nil, ---@type "yolo"|"safe"|nil
  merge = "squash", ---@type "squash"|"ff"|"merge"
  model = nil, ---@type string|nil  passed to `claude --model`
  claude_cmd = "claude", ---deprecated alias for adapters.claude_code.cmd
  adapter = "claude_code", ---@type string  default adapter for spawns without --adapter
  ---Per-adapter overrides: `adapters = { codex = { cmd = "...", model = "..." } }`
  adapters = {}, ---@type table<string, { cmd?: string, model?: string }>
  ---Notify when a run finishes (done/failed) and the dashboard is closed.
  ---true: vim.notify; false: silent; function: called with the run instead.
  notify = true, ---@type boolean|fun(run: hangar.Run)
  ---Max simultaneously running agent processes (across all repos); extra
  ---spawns park as "queued" and start as slots free up. nil = unlimited.
  max_concurrent = nil, ---@type integer|nil
}

---@param opts hangar.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

---Statusline component: "hangar 2● 1✓" (running / awaiting review), "" when idle.
---Cached; safe to call on every redraw. `status_counts()` returns the raw table.
function M.status()
  return require("hangar.status").text()
end

function M.status_counts()
  return require("hangar.status").counts()
end

local PERMISSION_MODES = { yolo = "bypassPermissions", safe = "acceptEdits" }

local MAX_FLEET = 8

---Parse `:Hangar spawn` args: flags (--yolo/--safe/--model m/--adapter a/--n c) then prompt.
---@return table|nil parsed { prompt, permission_mode, model, adapter, n }
---@return string|nil err
local function parse_spawn_args(fargs)
  local permission, model, adapter, n
  local i = 1
  while i <= #fargs do
    local a = fargs[i]
    if a == "--yolo" or a == "--safe" then
      permission = PERMISSION_MODES[a:sub(3)]
    elseif a == "--model" or a == "--adapter" or a == "--n" then
      local value = fargs[i + 1]
      if not value then
        return nil, a .. " needs a value"
      end
      if a == "--model" then
        model = value
      elseif a == "--adapter" then
        adapter = value
      else
        n = tonumber(value)
        if not n or n ~= math.floor(n) or n < 1 or n > MAX_FLEET then
          return nil, ("--n needs a whole number between 1 and %d"):format(MAX_FLEET)
        end
      end
      i = i + 1
    else
      break -- prompt starts here
    end
    i = i + 1
  end
  if not permission then
    local default = M.config.default_permission
    permission = default and PERMISSION_MODES[default]
  end
  if not permission then
    return nil,
      "pass --yolo (full tool access) or --safe (edits only, no shell), "
        .. 'or set setup({ default_permission = "yolo"|"safe" })'
  end
  local prompt = table.concat(vim.list_slice(fargs, i), " ")
  if vim.trim(prompt) == "" then
    return nil, "usage: :Hangar spawn [--yolo|--safe] [--adapter <a>] [--model <m>] <prompt>"
  end
  return { prompt = prompt, permission_mode = permission, model = model, adapter = adapter, n = n }
end

M._parse_spawn_args = parse_spawn_args -- exposed for tests

---@param prompt string
---@param opts table|nil { permission_mode?, model?, adapter?, n? }  Lua API entry point
---@return hangar.Run|hangar.Run[]|nil run single run, or the list of attempts when n > 1
function M.spawn(prompt, opts)
  opts = opts or {}
  if not opts.permission_mode then
    local default = M.config.default_permission
    opts.permission_mode = default and PERMISSION_MODES[default]
  end
  if not opts.permission_mode then
    vim.notify("[hangar] spawn needs permission_mode (or default_permission in setup)", vim.log.levels.ERROR)
    return
  end
  local runner = require("hangar.runner")
  local n = opts.n or 1
  opts.n = nil

  if n == 1 then
    local run, err = runner.spawn(prompt, opts)
    if not run then
      vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
      return
    end
    vim.notify(("[hangar] spawned run %s on branch %s"):format(run.id, run.branch))
    return run
  end

  -- best-of-n: same prompt, n isolated attempts sharing a group id
  local group = os.date("g%H%M%S")
  local runs = {}
  for attempt = 1, n do
    local run, err = runner.spawn(prompt, vim.tbl_extend("force", opts, { group = group, attempt = attempt }))
    if not run then
      vim.notify("[hangar] attempt " .. attempt .. ": " .. err, vim.log.levels.ERROR)
      break
    end
    runs[#runs + 1] = run
  end
  if #runs > 0 then
    vim.notify(("[hangar] spawned %d attempts of the same prompt (group %s)"):format(#runs, group))
  end
  return runs
end

---:Hangar command dispatcher.
function M._command(cmd)
  local fargs = cmd.fargs
  local sub = fargs[1]

  if not sub then
    require("hangar.ui.dashboard").open()
    return
  end

  if sub == "spawn" then
    local parsed, err = parse_spawn_args(vim.list_slice(fargs, 2))
    if not parsed then
      vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
      return
    end
    M.spawn(parsed.prompt, {
      permission_mode = parsed.permission_mode,
      model = parsed.model,
      adapter = parsed.adapter,
      n = parsed.n,
    })
  elseif sub == "kill" then
    local ok, err = require("hangar.runner").kill(fargs[2])
    if not ok then
      vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
    end
  elseif sub == "clean" then
    local root, err = require("hangar.worktree").root()
    if not root then
      vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
      return
    end
    local count = require("hangar.runner").clean(root)
    vim.notify(("[hangar] cleaned %d run(s)"):format(count))
  else
    vim.notify("[hangar] unknown subcommand: " .. sub, vim.log.levels.ERROR)
  end
end

function M._complete(arg_lead, cmd_line)
  local args = vim.split(cmd_line, "%s+", { trimempty = true })
  -- completing the subcommand itself
  if #args == 1 or (#args == 2 and arg_lead ~= "") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arg_lead)
    end, { "spawn", "kill", "clean" })
  end
  if args[2] == "spawn" then
    if args[#args] == "--adapter" or (arg_lead ~= "" and args[#args - 1] == "--adapter") then
      return vim.tbl_filter(function(s)
        return vim.startswith(s, arg_lead)
      end, require("hangar.adapters").available())
    end
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arg_lead)
    end, { "--yolo", "--safe", "--model", "--adapter", "--n" })
  end
  if args[2] == "kill" then
    local runner = require("hangar.runner")
    runner.load()
    local ids = {}
    for id, run in pairs(runner.runs) do
      if run.status == "running" then
        ids[#ids + 1] = id
      end
    end
    return ids
  end
  return {}
end

return M
