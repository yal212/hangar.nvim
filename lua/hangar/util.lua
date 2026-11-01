---Small shared helpers. Kept dependency-free so any module can require it.
local M = {}

local PREFIX = "[hangar] "

---Longest prefix of `s` that fits in `max_bytes` without splitting a UTF-8
---character — a plain `s:sub(1, n)` can cut a CJK or emoji character in half
---and leave invalid bytes in a buffer or a commit message. Pure Lua with no
---vim.fn: adapters call it while parsing inside a job's stdout callback, which
---is a fast event context.
---@param s string
---@param max_bytes integer
---@return string
function M.utf8_prefix(s, max_bytes)
  if #s <= max_bytes then
    return s
  end
  local cut = math.max(max_bytes, 0)
  -- the byte after the cut is a continuation byte (0b10xxxxxx): the cut lands
  -- inside a character, so back up to that character's first byte
  while cut > 0 do
    local b = s:byte(cut + 1)
    if b < 0x80 or b >= 0xC0 then
      break
    end
    cut = cut - 1
  end
  return s:sub(1, cut)
end

---Notify at INFO with the plugin prefix.
---@param msg string
function M.notify(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.INFO)
end

---Error text for display. Callers pass the `err` half of an `(ok, err)` pair,
---which is typed `string|nil` even where it cannot be nil in practice — so
---accept nil rather than raising a concat error on top of the real failure.
---@param msg string|nil
---@return string
local function text(msg)
  return msg == nil and "unknown error" or tostring(msg)
end

---Notify at WARN with the plugin prefix.
---@param msg string|nil
function M.notify_warn(msg)
  vim.notify(PREFIX .. text(msg), vim.log.levels.WARN)
end

---Notify at ERROR with the plugin prefix. The plugin's convention is that
---inner functions return `(nil, err)` and only the outermost caller notifies.
---@param msg string|nil
function M.notify_err(msg)
  vim.notify(PREFIX .. text(msg), vim.log.levels.ERROR)
end

return M
