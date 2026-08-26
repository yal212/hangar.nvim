---Dashboard actions. Each takes the run it operates on rather than reading the
---cursor, so the dashboard's keymaps stay one-liners and the actions can be
---tested without a window open.
local util = require("hangar.util")
local runner = require("hangar.runner")

local M = {}

---Close the dashboard before handing the screen to another float.
local function close_dashboard()
  require("hangar.ui.dashboard").close()
end

---@param run hangar.Run
function M.transcript(run)
  close_dashboard()
  require("hangar.ui.transcript").open(run.id)
end

---@param run hangar.Run
function M.review(run)
  -- refuse before closing the dashboard, so a `d` on a queued row is a no-op
  -- rather than costing the user the window they were reading
  local review = require("hangar.ui.review")
  local ok, err = review.reviewable(run)
  if not ok then
    util.notify_err(err)
    return
  end
  close_dashboard()
  review.open(run.id)
end

---Sibling attempts of a merged best-of-n run that are safe to discard.
---@param run hangar.Run
---@return hangar.Run[]
function M.discardable_siblings(run)
  if not run.group then
    return {}
  end
  return vim.tbl_filter(function(r)
    return r.group == run.group and r.id ~= run.id and r.status ~= "running" and r.status ~= "merged"
  end, runner.list(run.root))
end

---@param run hangar.Run
function M.merge(run)
  local strategy = require("hangar").config.merge
  local choice = vim.fn.confirm(("Merge %s (%s) into your branch?"):format(run.id, strategy), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local ok, err, meta = runner.merge(run.id)
  if not ok and meta and meta.rebaseable then
    -- the agent branch is disposable; rebasing it onto HEAD usually resolves
    choice = vim.fn.confirm(
      ("Merge failed: %s\n\nRebase %s onto your HEAD and retry the merge?"):format(err, run.id),
      "&Rebase and retry\n&Cancel",
      2
    )
    if choice ~= 1 then
      return
    end
    ok, err = runner.rebase_and_merge(run.id)
  end
  if not ok then
    util.notify_err(err)
    return
  end
  util.notify(("merged %s"):format(run.id))

  local siblings = M.discardable_siblings(run)
  if #siblings == 0 then
    return
  end
  choice = vim.fn.confirm(
    ("Discard the %d other attempt(s) of this prompt? Worktrees and branches are deleted."):format(#siblings),
    "&Yes\n&No",
    1
  )
  if choice ~= 1 then
    return
  end
  for _, sibling in ipairs(siblings) do
    local sok, serr = runner.discard(sibling.id)
    if not sok then
      util.notify_err(serr)
    end
  end
end

---@param run hangar.Run
function M.discard(run)
  local choice = vim.fn.confirm(("Discard %s? Worktree and branch are deleted."):format(run.id), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local ok, err = runner.discard(run.id)
  if not ok then
    util.notify_err(err)
  end
end

---@param run hangar.Run
function M.kill(run)
  local ok, err = runner.kill(run.id)
  if not ok then
    util.notify_err(err)
  end
end

---@param run hangar.Run
function M.iterate(run)
  vim.ui.input({ prompt = ("Feedback for %s: "):format(run.id) }, function(feedback)
    if not feedback or vim.trim(feedback) == "" then
      return
    end
    local new_run, err = runner.iterate(run.id, feedback)
    if new_run then
      util.notify(("iterating on %s as run %s"):format(run.id, new_run.id))
    else
      util.notify_err(err)
    end
  end)
end

---@param run hangar.Run
function M.resume(run)
  local ok, err = runner.resume(run.id)
  if ok then
    util.notify(("resumed %s in its worktree"):format(run.id))
  else
    util.notify_err(err)
  end
end

---Prompt for a new run. The only action that needs no existing run.
function M.spawn()
  vim.ui.input({ prompt = "Agent prompt: " }, function(prompt)
    if not prompt or vim.trim(prompt) == "" then
      return
    end
    local hangar = require("hangar")
    if hangar.config.default_permission then
      hangar.spawn(prompt)
      return
    end
    vim.ui.select({ "yolo (full tool access)", "safe (edits only, no shell)" }, {
      prompt = "Permission mode for this run:",
    }, function(choice)
      if not choice then
        return
      end
      local mode = choice:match("^yolo") and "bypassPermissions" or "acceptEdits"
      hangar.spawn(prompt, { permission_mode = mode })
    end)
  end)
end

return M
