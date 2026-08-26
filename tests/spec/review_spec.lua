---Review float: the changed-file listing a run is judged from, and the
---"has not started yet" guard in front of it.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  local runner = require("hangar.runner")
  local worktree = require("hangar.worktree")
  local review = require("hangar.ui.review")

  -- reviewable(): the fc0ea03 guard. A queued run has no base/worktree/branch —
  -- they are assigned together when it leaves the queue — so there is nothing
  -- to diff against. Checked on `base` rather than status, because a run killed
  -- while queued keeps base == nil too.
  local queued = { id = "rv0", root = "/some/repo", status = "queued", started = 1, events = {}, prompt = "later" }
  local ok, why = review.reviewable(queued)
  check(ok == false, "review: a run that never started is not reviewable")
  check(why == "run rv0 has not started yet", "review: the refusal names the run")
  queued.base = "deadbeefdeadbeef"
  check(review.reviewable(queued) == true, "review: a run with a base commit is reviewable")

  local repo = harness.git_repo("review")
  sh(repo, { "git", "commit", "--allow-empty", "-m", "root" })
  for _, name in ipairs({ "keep.txt", "gone.txt" }) do
    local f = assert(io.open(repo .. "/" .. name, "w"))
    f:write("original\n")
    f:close()
  end
  sh(repo, { "git", "add", "-A" })
  sh(repo, { "git", "commit", "-m", "seed" })

  local prev = assert(vim.uv.cwd())
  vim.fn.chdir(repo)
  local root = assert(worktree.root())
  local wt = worktree.create(root, "rv1")

  -- one modified, one deleted, one untracked — the three statuses the float
  -- colours differently (STATUS_HL in ui/review.lua)
  local mod = assert(io.open(wt.path .. "/keep.txt", "w"))
  mod:write("changed\n")
  mod:close()
  os.remove(wt.path .. "/gone.txt")
  local added = assert(io.open(wt.path .. "/brand-new.txt", "w"))
  added:write("hello\n")
  added:close()

  runner.runs["rv1"] = {
    id = "rv1",
    root = root,
    status = "done",
    started = 10,
    events = {},
    prompt = "touch some files",
    base = wt.base,
    branch = wt.branch,
    worktree = wt.path,
  }

  review.open("rv1")
  local win = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")

  check(
    text:find(("rv1 — 3 file(s) changed vs %s"):format(wt.base:sub(1, 8)), 1, true) ~= nil,
    "review: the header counts the changed files and names the base commit"
  )
  check(text:find("  M  keep.txt", 1, true) ~= nil, "review: a modified file is listed as M")
  check(text:find("  D  gone.txt", 1, true) ~= nil, "review: a deleted file is listed as D")
  check(text:find("  A  brand-new.txt", 1, true) ~= nil, "review: an untracked file is listed as A")
  check(text:find("<CR> diff file", 1, true) ~= nil, "review: the key hints are rendered")
  check(not vim.bo[0].modifiable, "review: the float is read-only")

  -- the cursor starts on the first file, so <CR> diffs a file rather than the header
  local first_file_line
  for i, l in ipairs(lines) do
    if l:find("keep.txt", 1, true) or l:find("gone.txt", 1, true) or l:find("brand-new.txt", 1, true) then
      first_file_line = i
      break
    end
  end
  check(vim.api.nvim_win_get_cursor(win)[1] == first_file_line, "review: the cursor opens on the first changed file")
  vim.api.nvim_win_close(win, true)

  -- a run whose worktree matches its base has nothing to show
  local clean = worktree.create(root, "rv2")
  runner.runs["rv2"] = {
    id = "rv2",
    root = root,
    status = "done",
    started = 11,
    events = {},
    prompt = "did nothing",
    base = clean.base,
    branch = clean.branch,
    worktree = clean.path,
  }
  review.open("rv2")
  local empty_win = vim.api.nvim_get_current_win()
  local empty = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  check(empty:find("0 file(s) changed", 1, true) ~= nil, "review: an untouched run reports zero files")
  check(empty:find("  (no changes)", 1, true) ~= nil, "review: an untouched run says so explicitly")
  vim.api.nvim_win_close(empty_win, true)

  -- a queued run refuses at the door instead of erroring on a nil base
  runner.runs["rv3"] = { id = "rv3", root = root, status = "queued", started = 12, events = {}, prompt = "waiting" }
  local notified
  local real_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    notified = msg
  end
  local opened = pcall(review.open, "rv3")
  vim.notify = real_notify
  check(opened, "review: opening a queued run does not raise")
  check(
    notified and tostring(notified):find("rv3 has not started yet", 1, true) ~= nil,
    "review: opening a queued run explains why it cannot"
  )

  for _, id in ipairs({ "rv1", "rv2", "rv3" }) do
    runner.runs[id] = nil
  end
  worktree.remove({ root = root, worktree = wt.path, branch = wt.branch })
  worktree.remove({ root = root, worktree = clean.path, branch = clean.branch })
  vim.fn.chdir(prev)
end
