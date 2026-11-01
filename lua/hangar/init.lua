---hangar.nvim — run a fleet of coding agents in parallel git worktrees.
local util = require("hangar.util")

local M = {}

M.version = "0.2.0"

---Resolved configuration. `M.config` is this shape after `setup()` has merged
---the user's options in; every field is present, though several may be nil.
---@class hangar.Config
---@field default_permission "yolo"|"safe"|nil permission mode for spawns with no --yolo/--safe flag
---@field merge "squash"|"ff"|"merge" strategy used when merging a run's branch back
---@field model string|nil model passed to the agent CLI, e.g. `claude --model`
---@field claude_cmd string deprecated alias for adapters.claude_code.cmd; removed in 0.3.0
---@field adapter string default adapter for spawns with no --adapter flag
---@field adapters table<string, { cmd?: string, model?: string }> per-adapter cmd/model overrides
---@field notify boolean|fun(run: hangar.Run) true: vim.notify; false: silent; function: called with the run
---@field max_concurrent integer|nil max simultaneous agent processes across all repos; nil = unlimited

---What `setup()` accepts: the same options as |hangar.Config|, all optional.
---Kept separate so a partial table is not a missing-fields error at every
---call site — which is how everyone actually calls setup().
---@class hangar.Opts
---@field default_permission? "yolo"|"safe"
---@field merge? "squash"|"ff"|"merge"
---@field model? string
---@field claude_cmd? string
---@field adapter? string
---@field adapters? table<string, { cmd?: string, model?: string }>
---@field notify? boolean|fun(run: hangar.Run)
---@field max_concurrent? integer

---@type hangar.Config
M.config = {
  ---Default permission mode for spawns without an explicit --yolo/--safe flag.
  ---nil (default) means every spawn must pass one; "yolo" or "safe" opt in.
  default_permission = nil,
  merge = "squash",
  model = nil, ---passed to `claude --model`
  claude_cmd = "claude", ---deprecated alias for adapters.claude_code.cmd
  adapter = "claude_code", ---default adapter for spawns without --adapter
  ---Per-adapter overrides: `adapters = { codex = { cmd = "...", model = "..." } }`
  adapters = {},
  ---Notify when a run finishes (done/failed) and the dashboard is closed.
  ---true: vim.notify; false: silent; function: called with the run instead.
  notify = true,
  ---Max simultaneously running agent processes (across all repos); extra
  ---spawns park as "queued" and start as slots free up. nil = unlimited.
  max_concurrent = nil,
}

---Accepted shape per option. `types` is checked with type(); `values` (when
---present) restricts a string to a fixed set; `check` (when present) is a
---predicate on a value of the right type, described by `expect`. Every key here
---must also exist in M.config — the two are cross-checked by
---scripts/check-docs.lua.
local SCHEMA = {
  default_permission = { types = { "string" }, values = { yolo = true, safe = true } },
  merge = { types = { "string" }, values = { squash = true, ff = true, merge = true } },
  model = { types = { "string" } },
  claude_cmd = { types = { "string" } },
  adapter = { types = { "string" } },
  adapters = { types = { "table" } },
  notify = { types = { "boolean", "function" } },
  max_concurrent = {
    types = { "number" },
    -- 0 would park every spawn in the queue forever
    check = function(n)
      return n >= 1 and n == math.floor(n)
    end,
    expect = "a whole number >= 1",
  },
}

---Validate a user-supplied options table. Returns the problems as a list of
---strings rather than raising: a bad value in someone's init.lua should not
---abort the rest of their config.
---
---Note: this is hand-rolled rather than using vim.validate, because the table
---form is deprecated on nightly and the replacement does not exist on 0.10 —
---and CI tests both ends of that range.
---@param opts table
---@return string[] problems
---@return table<any, true> rejected the keys behind those problems
local function validate(opts)
  local problems, rejected = {}, {}
  local known = vim.tbl_keys(SCHEMA)
  table.sort(known)
  for key, value in pairs(opts) do
    local rule = SCHEMA[key]
    local before = #problems
    if not rule then
      local hint = ""
      -- a near-miss is almost always a typo, so name the likely intent
      for _, candidate in ipairs(known) do
        if vim.startswith(candidate, tostring(key):sub(1, 3)) then
          hint = (" — did you mean %q?"):format(candidate)
          break
        end
      end
      problems[#problems + 1] = ("unknown option %q%s (valid: %s)"):format(
        tostring(key),
        hint,
        table.concat(known, ", ")
      )
    elseif not vim.list_contains(rule.types, type(value)) then
      problems[#problems + 1] = ("option %q expects %s, got %s"):format(
        key,
        table.concat(rule.types, " or "),
        type(value)
      )
    elseif rule.values and not rule.values[value] then
      local allowed = vim.tbl_keys(rule.values)
      table.sort(allowed)
      problems[#problems + 1] = ("option %q must be one of: %s (got %q)"):format(
        key,
        table.concat(allowed, ", "),
        value
      )
    elseif rule.check and not rule.check(value) then
      problems[#problems + 1] = ("option %q must be %s (got %s)"):format(key, rule.expect, tostring(value))
    end
    if #problems > before then
      rejected[key] = true
    end
  end
  table.sort(problems)
  return problems, rejected
end

M._SCHEMA = SCHEMA -- exposed for tests and scripts/check-docs.lua
M._validate = validate -- exposed for tests

---@param opts hangar.Opts?
function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    util.notify_err("setup() expects a table of options")
    return
  end
  local problems, rejected = validate(opts)
  for _, problem in ipairs(problems) do
    util.notify_err("setup(): " .. problem)
  end
  -- a rejected option keeps its previous value: reporting it and then
  -- applying it anyway would leave the plugin running on the bad value
  local accepted = {}
  for key, value in pairs(opts) do
    if not rejected[key] then
      accepted[key] = value
    end
  end
  if accepted.claude_cmd ~= nil then
    util.notify_warn(
      "config.claude_cmd is deprecated and will be removed in 0.3.0 — use adapters = { claude_code = { cmd = ... } }"
    )
  end
  M.config = vim.tbl_deep_extend("force", M.config, accepted)
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

---Statuses M.kill accepts (see runner.kill): a live job, a run parked in the
---queue, or one still alive after an nvim restart. Anything else is finished.
local KILLABLE = { running = true, queued = true, detached = true }

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
    util.notify_err("spawn needs permission_mode (or default_permission in setup)")
    return
  end
  local runner = require("hangar.runner")
  local n = opts.n or 1
  opts.n = nil

  if n == 1 then
    local run, err = runner.spawn(prompt, opts)
    if not run then
      util.notify_err(err)
      return
    end
    util.notify(("spawned run %s on branch %s"):format(run.id, run.branch))
    return run
  end

  -- best-of-n: same prompt, n isolated attempts sharing a group id
  local group = os.date("g%H%M%S")
  local runs = {}
  for attempt = 1, n do
    local run, err = runner.spawn(prompt, vim.tbl_extend("force", opts, { group = group, attempt = attempt }))
    if not run then
      util.notify_err("attempt " .. attempt .. ": " .. err)
      break
    end
    runs[#runs + 1] = run
  end
  if #runs > 0 then
    util.notify(("spawned %d attempts of the same prompt (group %s)"):format(#runs, group))
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
      util.notify_err(err)
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
      util.notify_err(err)
    end
  elseif sub == "clean" then
    local root, err = require("hangar.worktree").root()
    if not root then
      util.notify_err(err)
      return
    end
    local count = require("hangar.runner").clean(root)
    util.notify(("cleaned %d run(s)"):format(count))
  else
    util.notify_err("unknown subcommand: " .. sub)
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
      if KILLABLE[run.status] and vim.startswith(id, arg_lead) then
        ids[#ids + 1] = id
      end
    end
    table.sort(ids) -- pairs() order is arbitrary; the menu should not shuffle
    return ids
  end
  return {}
end

return M
