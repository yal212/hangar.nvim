---Fleet status for statuslines: `require("hangar").status()` -> "hangar 2 ● 1 ✓".
---Cheap enough to call on every redraw: results are cached and only
---recomputed when a run changes (User HangarRunUpdate) or the cwd moves.
local M = {}

local text_cache = {} ---@type table<string, string> root -> rendered text
local root_cache = {} ---@type table<string, string|false> cwd -> repo root (false = not a repo)
local subscribed = false

local function subscribe()
  if subscribed then
    return
  end
  subscribed = true
  local group = vim.api.nvim_create_augroup("HangarStatus", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "HangarRunUpdate",
    callback = function()
      text_cache = {}
    end,
  })
end

---Repo root for the current cwd, resolved through git once then cached.
local function current_root()
  local cwd = vim.uv.cwd()
  local root = root_cache[cwd]
  if root == nil then
    root = require("hangar.worktree").root(cwd) or false
    root_cache[cwd] = root
  end
  return root or nil
end

---Run counts for the current repo, or nil outside a git repo.
---@return { running: integer, done: integer, failed: integer }|nil
function M.counts()
  subscribe()
  local root = current_root()
  if not root then
    return nil
  end
  local counts = { running = 0, done = 0, failed = 0 }
  for _, run in ipairs(require("hangar.runner").list(root)) do
    if counts[run.status] then
      counts[run.status] = counts[run.status] + 1
    end
  end
  return counts
end

---Statusline string; "" when there is nothing to show.
---@return string
function M.text()
  subscribe()
  local root = current_root()
  if not root then
    return ""
  end
  local cached = text_cache[root]
  if cached ~= nil then
    return cached
  end
  local c = M.counts() or { running = 0, done = 0, failed = 0 }
  local parts = {}
  if c.running > 0 then
    parts[#parts + 1] = c.running .. " ●"
  end
  if c.done > 0 then
    parts[#parts + 1] = c.done .. " ✓"
  end
  if c.failed > 0 then
    parts[#parts + 1] = c.failed .. " ✗"
  end
  local text = #parts > 0 and ("hangar " .. table.concat(parts, " ")) or ""
  text_cache[root] = text
  return text
end

return M
