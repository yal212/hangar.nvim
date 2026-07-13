---Shared helpers for adapter parsers.
local M = {}

---Collapse whitespace and cap length for one-line transcript display.
---@param s string
---@param max integer
---@return string
function M.truncate(s, max)
  s = s:gsub("%s+", " ")
  if #s > max then
    s = s:sub(1, max - 3) .. "..."
  end
  return s
end

---Summarize a tool_use input table into a short single-line string.
---@param input any
---@return string
function M.input_summary(input)
  if type(input) ~= "table" then
    return ""
  end
  for _, key in ipairs({ "file_path", "filePath", "path", "pattern", "command", "prompt", "query", "url", "patchText" }) do
    local v = input[key]
    if type(v) == "string" and v ~= "" then
      return M.truncate(v, 60)
    end
  end
  return ""
end

return M
