---Shared data + actions for the optional run pickers (telescope, fzf-lua).
---The core plugin never requires the host picker plugins; the wrappers do.
local util = require("hangar.util")
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

---@param id string
function M.open_transcript(id)
  require("hangar.ui.transcript").open(id)
end

---@param id string
function M.open_review(id)
  require("hangar.ui.review").open(id)
end

---Prompt for feedback and spawn a follow-up run. No-op on an empty answer.
---@param id string
function M.iterate(id)
  vim.ui.input({ prompt = ("Feedback for %s: "):format(id) }, function(feedback)
    if not feedback or vim.trim(feedback) == "" then
      return
    end
    local run, err = require("hangar.runner").iterate(id, feedback)
    if run then
      util.notify(("iterating on %s as run %s"):format(id, run.id))
    else
      util.notify_err(err)
    end
  end)
end

---Delete a run's worktree and branch, after confirmation.
---@param id string
function M.discard(id)
  local choice = vim.fn.confirm(("Discard %s? Worktree and branch are deleted."):format(id), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local ok, err = require("hangar.runner").discard(id)
  if not ok then
    util.notify_err(err)
  end
end

---The actions both picker frontends expose, in menu order. Each frontend maps
---these keys to `run`, so adding an action is a one-line change here instead of
---the same closure written out in both wrappers.
---@type { name: string, fzf: string, telescope: string, default: boolean|nil, run: fun(id: string) }[]
M.actions = {
  { name = "transcript", fzf = "default", telescope = "<CR>", default = true, run = M.open_transcript },
  { name = "review", fzf = "ctrl-d", telescope = "<C-d>", run = M.open_review },
  { name = "iterate", fzf = "ctrl-e", telescope = "<C-e>", run = M.iterate },
  { name = "discard", fzf = "ctrl-x", telescope = "<C-x>", run = M.discard },
}

return M
