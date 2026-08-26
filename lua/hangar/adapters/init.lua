---Adapter registry: resolve adapter modules by name and validate the contract.
---Contract: `name` string, `build_cmd(opts) -> argv`, `parse_line(line) -> event|nil`.
---Optional: `unsupported_modes` table<permission_mode, reason> — spawn fails fast
---with the reason instead of launching a run that would hang.
local M = {}

---One parsed line of an agent CLI's stream. Adapters normalise every CLI's
---own wire format into this shape; the runner folds it into the run record
---(runner.lua:112) and |hangar.ui.transcript| renders it. Only `kind` is
---always present — which of the rest are set depends on the kind.
---@class hangar.Event
---@field kind "init"|"text"|"tool_use"|"tool_result"|"result"|"batch"
---@field events hangar.Event[]|nil kind "batch": sub-events to fold in order
---@field text string|nil kinds "text", "tool_result", and an errored "result"
---@field delta boolean|nil kind "text": a streamed fragment, appended to the previous event
---@field tool string|nil kind "tool_use": the tool's name
---@field summary string|nil kind "tool_use": one-line argument summary, "" when there is none
---@field is_error boolean|nil kinds "tool_result" and "result"
---@field turns integer|nil kind "result"
---@field cost number|nil kind "result", in USD
---@field duration_ms number|nil kind "result"
---@field model string|nil kind "init": the model the CLI actually chose
---@field session_id string|nil kind "init": resume handle, see build_resume_cmd
---@field partial boolean|nil kind "result": an incremental step, not the final result

---What every module in this directory must implement. Enforced at runtime in
---|M.get| — keep the two in step.
---@class hangar.Adapter
---@field name string
---@field build_cmd fun(opts: hangar.SpawnCmdOpts): string[]
---@field parse_line fun(line: string): hangar.Event|nil
---@field build_resume_cmd? fun(opts: hangar.ResumeCmdOpts): string[]
---@field unsupported_modes? table<string, string> permission_mode -> reason the adapter refuses it

---@class hangar.SpawnCmdOpts
---@field prompt string
---@field permission_mode "acceptEdits"|"bypassPermissions"
---@field model string|nil
---@field cmd string|nil executable override for this adapter
---@field cwd string|nil worktree path the run executes in (for CLIs that need it as a flag)

---@class hangar.ResumeCmdOpts: hangar.SpawnCmdOpts
---@field session_id string session to resume (captured from the init event)

---@param name string
---@return hangar.Adapter|nil adapter
---@return string|nil err
function M.get(name)
  if type(name) ~= "string" or name == "" then
    return nil, "adapter name required"
  end
  if name == "init" or name == "util" then
    return nil, "not an adapter: " .. name
  end
  local ok, adapter = pcall(require, "hangar.adapters." .. name)
  if not ok then
    return nil, ("unknown adapter %q (available: %s)"):format(name, table.concat(M.available(), ", "))
  end
  if
    type(adapter) ~= "table"
    or type(adapter.name) ~= "string"
    or type(adapter.build_cmd) ~= "function"
    or type(adapter.parse_line) ~= "function"
  then
    return nil, ("adapter %q does not implement the contract (name, build_cmd, parse_line)"):format(name)
  end
  return adapter
end

---Names of all adapters shipped on the runtimepath.
---@return string[]
function M.available()
  local names = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/hangar/adapters/*.lua", true)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    if name ~= "init" and name ~= "util" and not vim.list_contains(names, name) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

return M
