---Shared data + actions for the optional run pickers (telescope, fzf-lua).
---The core plugin never requires the host picker plugins; the wrappers do.
local M = {}

local icons = require("hangar.ui.icons")

---Runs for the current repo, newest first, each with a one-line display.
---@return { run: hangar.Run, display: string }[]|nil entries
---@return string|nil err
function M.entries()
  local root, err = require("hangar.worktree").root()
  if not root then
    return nil, err
  end
  local entries = {}
  for _, run in ipairs(require("hangar.runner").list(root)) do
    local stats = {}
    if run.cost then
      stats[#stats + 1] = ("$%.2f"):format(run.cost)
    end
    if run.turns then
      stats[#stats + 1] = run.turns .. " turns"
    end
    local prompt = run.prompt:gsub("%s+", " ")
    entries[#entries + 1] = {
      run = run,
      display = ("%s %-9s %-8s %s%s"):format(
        icons.get(run.status).icon,
        run.id,
        run.status,
        prompt:sub(1, 60) .. (#prompt > 60 and "…" or ""),
        #stats > 0 and ("  (" .. table.concat(stats, ", ") .. ")") or ""
      ),
    }
  end
  return entries
end

function M.open_transcript(id)
  require("hangar.ui.transcript").open(id)
end

function M.open_review(id)
  require("hangar.ui.review").open(id)
end

function M.discard(id)
  local choice = vim.fn.confirm(("Discard %s? Worktree and branch are deleted."):format(id), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local ok, err = require("hangar.runner").discard(id)
  if not ok then
    vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
  end
end

return M
