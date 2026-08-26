---Adapter for the Gemini CLI (`gemini -p <prompt> -o stream-json`).
---Stream-json JSONL events (from the CLI's StreamJsonFormatter):
---  init, message (role user|assistant, assistant arrives as deltas),
---  tool_use, tool_result, result (status success|error, token stats only).
---No USD cost or turn count in the stream, so those stay nil.
local util = require("hangar.adapters.util")

---@class hangar.adapter.gemini: hangar.Adapter
local M = { name = "gemini" }

local APPROVAL = {
  acceptEdits = "auto_edit",
  bypassPermissions = "yolo",
}

---@param opts hangar.SpawnCmdOpts
---@return string[]
function M.build_cmd(opts)
  local cmd = {
    opts.cmd or "gemini",
    "-p",
    opts.prompt,
    "-o",
    "stream-json",
    -- worktrees are fresh folders; without this gemini downgrades the
    -- approval mode to "default" and a headless run stalls on prompts
    "--skip-trust",
    "--approval-mode",
    APPROVAL[opts.permission_mode] or APPROVAL.acceptEdits,
  }
  if opts.model then
    vim.list_extend(cmd, { "-m", opts.model })
  end
  return cmd
end

---@param line string
---@return table|nil event
function M.parse_line(line)
  local obj = util.decode_line(line)
  if not obj then
    return nil
  end

  if obj.type == "init" then
    return { kind = "init", model = obj.model, session_id = obj.session_id }
  end

  if obj.type == "message" then
    -- the user message is just the prompt echoed back; skip it
    if obj.role == "assistant" and type(obj.content) == "string" and obj.content ~= "" then
      return { kind = "text", text = obj.content, delta = obj.delta == true }
    end
    return nil
  end

  if obj.type == "tool_use" then
    return {
      kind = "tool_use",
      tool = obj.tool_name or "?",
      summary = util.input_summary(obj.parameters),
    }
  end

  if obj.type == "tool_result" then
    local text = type(obj.output) == "string" and obj.output or ""
    local is_error = obj.status == "error"
    if is_error and type(obj.error) == "table" and type(obj.error.message) == "string" then
      text = obj.error.message
    end
    return { kind = "tool_result", text = util.truncate(text, 120), is_error = is_error }
  end

  if obj.type == "result" then
    local is_error = obj.status == "error"
    local msg
    if type(obj.error) == "table" and type(obj.error.message) == "string" then
      msg = obj.error.message
    end
    local stats = type(obj.stats) == "table" and obj.stats or {}
    return {
      kind = "result",
      is_error = is_error,
      text = msg,
      duration_ms = tonumber(stats.duration_ms),
    }
  end

  return nil -- unknown event types are ignored; the CLI adds types over time
end

return M
