---Adapter for the OpenCode CLI (`opencode run --format json`).
---JSONL events wrap a `part` object: step_start, text, tool_use (with a
---completed-state part carrying input and output), step_finish (per-step
---cost + tokens; there is no single final result event, so step stats are
---emitted as partial results the runner accumulates).
local util = require("hangar.adapters.util")

local M = { name = "opencode" }

-- opencode has no headless equivalent of "edits only": without --auto it
-- waits on interactive permission prompts that a spawned run can never answer
M.unsupported_modes = {
  acceptEdits = "opencode has no headless safe mode; spawn with --yolo",
}

---@param opts hangar.SpawnCmdOpts
---@return string[]
function M.build_cmd(opts)
  local cmd = {
    opts.cmd or "opencode",
    "run",
    "--format",
    "json",
  }
  if opts.cwd then
    -- opencode resolves its project dir itself (it does not honor the
    -- spawn cwd reliably); pin it or the agent escapes the worktree
    vim.list_extend(cmd, { "--dir", opts.cwd })
  end
  -- acceptEdits is rejected at spawn (see unsupported_modes above)
  if opts.permission_mode == "bypassPermissions" then
    cmd[#cmd + 1] = "--auto"
  end
  if opts.model then
    vim.list_extend(cmd, { "-m", opts.model }) -- provider/model, e.g. anthropic/claude-haiku-4-5
  end
  cmd[#cmd + 1] = opts.prompt
  return cmd
end

---@param line string
---@return table|nil event
function M.parse_line(line)
  if line == "" then
    return nil
  end
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then
    return nil
  end
  local part = type(obj.part) == "table" and obj.part or {}

  if obj.type == "step_start" then
    return { kind = "init", session_id = obj.sessionID }
  end

  if obj.type == "text" then
    if type(part.text) == "string" and part.text ~= "" then
      return { kind = "text", text = part.text }
    end
    return nil
  end

  if obj.type == "tool_use" then
    -- one line carries the whole call: input and finished state
    local state = type(part.state) == "table" and part.state or {}
    local is_error = state.status == "error"
    local output = type(state.output) == "string" and state.output or ""
    return {
      kind = "batch",
      events = {
        { kind = "tool_use", tool = part.tool or "?", summary = util.input_summary(state.input) },
        { kind = "tool_result", text = util.truncate(output, 120), is_error = is_error },
      },
    }
  end

  if obj.type == "step_finish" then
    return { kind = "result", partial = true, cost = tonumber(part.cost) }
  end

  return nil -- unknown event types are ignored; the CLI adds types over time
end

return M
