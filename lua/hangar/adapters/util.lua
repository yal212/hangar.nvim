---Shared helpers for adapter parsers.
local M = {}

---Decode one line of a CLI's JSON stream. Returns nil for blank lines, invalid
---JSON, and any non-object payload — every adapter opens `parse_line` with this,
---and all of them treat an undecodable line as "ignore and keep going".
---@param line string
---@return table|nil obj
function M.decode_line(line)
  if line == "" then
    return nil
  end
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then
    return nil
  end
  return obj
end

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

-- first match wins: the most specific identifier each CLI puts in a tool call
local SUMMARY_KEYS = {
  "file_path",
  "filePath",
  "path",
  "pattern",
  "command",
  "prompt",
  "query",
  "url",
  "patchText",
}

---Summarize a tool_use input table into a short single-line string.
---@param input any
---@return string
function M.input_summary(input)
  if type(input) ~= "table" then
    return ""
  end
  for _, key in ipairs(SUMMARY_KEYS) do
    local v = input[key]
    if type(v) == "string" and v ~= "" then
      return M.truncate(v, 60)
    end
  end
  return ""
end

return M
