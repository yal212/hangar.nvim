---Small shared helpers. Kept dependency-free so any module can require it.
local M = {}

local PREFIX = "[hangar] "

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
