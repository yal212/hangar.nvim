---Adapter for the OpenAI Codex CLI (`codex exec --json`).
---Codex emits thread-event JSONL: thread.started, turn.started, item.started/
---item.completed (agent_message, command_execution, file_change, ...),
---turn.completed/turn.failed. Usage is tokens only, so `cost` stays nil.
local util = require("hangar.adapters.util")

local M = { name = "codex" }

---Codex has no per-tool approval prompt in exec mode; permissions map to
---its sandbox policy instead.
local SANDBOX = {
  acceptEdits = { "--sandbox", "workspace-write" },
  bypassPermissions = { "--dangerously-bypass-approvals-and-sandbox" },
}

---@param opts hangar.SpawnCmdOpts
---@return string[]
function M.build_cmd(opts)
  local cmd = {
    opts.cmd or "codex",
    "exec",
    "--json",
    "--ephemeral",
    "--skip-git-repo-check",
  }
  vim.list_extend(cmd, SANDBOX[opts.permission_mode] or SANDBOX.acceptEdits)
  if opts.model then
    vim.list_extend(cmd, { "-m", opts.model })
  end
  cmd[#cmd + 1] = opts.prompt
  return cmd
end

---Describe a file_change item's paths, e.g. "update a.lua, add b.lua".
local function changes_summary(changes)
  if type(changes) ~= "table" then
    return ""
  end
  local parts = {}
  for _, c in ipairs(changes) do
    if type(c) == "table" and type(c.path) == "string" then
      parts[#parts + 1] = (c.kind and (c.kind .. " ") or "") .. vim.fn.fnamemodify(c.path, ":t")
    end
  end
  return util.truncate(table.concat(parts, ", "), 60)
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

  if obj.type == "thread.started" then
    return { kind = "init", session_id = obj.thread_id }
  end

  if obj.type == "item.started" or obj.type == "item.completed" then
    local item = obj.item
    if type(item) ~= "table" then
      return nil
    end
    if item.type == "agent_message" and obj.type == "item.completed" then
      if type(item.text) == "string" and item.text ~= "" then
        return { kind = "text", text = item.text }
      end
      return nil
    end
    if item.type == "command_execution" then
      if obj.type == "item.started" then
        return { kind = "tool_use", tool = "shell", summary = util.truncate(item.command or "", 60) }
      end
      return {
        kind = "tool_result",
        text = util.truncate(item.aggregated_output or "", 120),
        is_error = tonumber(item.exit_code) ~= nil and tonumber(item.exit_code) ~= 0,
      }
    end
    if item.type == "file_change" and obj.type == "item.completed" then
      return { kind = "tool_use", tool = "edit", summary = changes_summary(item.changes) }
    end
    return nil -- reasoning, web_search, todo_list, ... are not shown
  end

  if obj.type == "turn.completed" then
    return { kind = "result", is_error = false }
  end

  if obj.type == "turn.failed" or obj.type == "error" then
    local msg = obj.message
    if type(obj.error) == "table" and type(obj.error.message) == "string" then
      msg = obj.error.message
    end
    return { kind = "result", is_error = true, text = type(msg) == "string" and msg or "codex run failed" }
  end

  return nil -- unknown event types are ignored; the CLI adds types over time
end

return M
