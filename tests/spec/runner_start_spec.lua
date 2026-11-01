---runner: an agent CLI that cannot be started fails the run cleanly, instead of
---leaving a "running" record with no process behind it.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local runner = require("hangar.runner")
    local hangar = require("hangar")
    local worktree = require("hangar.worktree")
    local repo = harness.git_repo("start")
    sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    local root = assert(worktree.root())
    hangar.setup({ notify = false })

    local function branch_exists(branch)
      return vim
        .system({ "git", "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch }, { cwd = root })
        :wait().code == 0
    end
    local function no_live_records()
      for _, r in pairs(runner.runs) do
        if r.adapter == "missing" and r.status == "running" then
          return false
        end
      end
      return true
    end

    -- direct spawn: an error, no record, no worktree, no branch
    local before = vim.tbl_count(runner.runs)
    local run, err = runner.spawn("p", { permission_mode = "bypassPermissions", adapter = "missing" })
    check(run == nil, "start: spawn with a missing CLI returns no run")
    check(
      err ~= nil and err:find(harness.MISSING_EXE, 1, true) ~= nil and err:find("checkhealth", 1, true) ~= nil,
      "start: the error names the executable and points at :checkhealth (" .. tostring(err) .. ")"
    )
    check(vim.tbl_count(runner.runs) == before and no_live_records(), "start: no run record is left behind")
    local leftovers = vim.fn.glob(worktree.home(root) .. "/*", false, true)
    check(#leftovers == 0, "start: no worktree directory is left behind")
    local branches = sh(root, { "git", "branch", "--list", "hangar/*" })
    check(branches == "", "start: no hangar branch is left behind")

    -- the :Hangar spawn path reports instead of raising a Lua error
    local notified
    local orig_notify = vim.notify
    vim.notify = function(msg)
      notified = msg
    end
    local ok = pcall(hangar.spawn, "p", { permission_mode = "bypassPermissions", adapter = "missing" })
    vim.notify = orig_notify
    check(ok and notified ~= nil and notified:find("could not start", 1, true) ~= nil, "start: hangar.spawn notifies")

    -- a queued run promoted onto a missing CLI fails, and frees its slot
    hangar.setup({ max_concurrent = 1 })
    local blocker = assert(runner.spawn("blocker", { permission_mode = "bypassPermissions", adapter = "fake" }))
    local queued = assert(runner.spawn("q", { permission_mode = "bypassPermissions", adapter = "missing" }))
    local after = assert(runner.spawn("after", { permission_mode = "bypassPermissions", adapter = "fake" }))
    check(queued.status == "queued" and after.status == "queued", "start: both runs queue behind the blocker")
    runner.kill(blocker.id)
    vim.wait(10000, function()
      return after.status ~= "queued"
    end, 50)
    check(queued.status == "failed" and queued.error ~= nil, "start: a promoted run with a missing CLI fails")
    check(queued.worktree == nil and queued.branch == nil, "start: the failed promotion keeps no worktree")
    check(after.status == "running", "start: the next queued run still gets the slot")
    runner.kill(after.id)
    vim.wait(10000, function()
      return after.exit_code ~= nil
    end, 50)
    hangar.setup({ max_concurrent = nil })
    hangar.config.max_concurrent = nil -- deep-extend cannot unset a key

    -- iterate (resume mode) onto a missing CLI: the old run keeps its worktree
    local w = worktree.create(root, "it1")
    local old = {
      id = "it1",
      root = root,
      worktree = w.path,
      branch = w.branch,
      base = w.base,
      adapter = "missing",
      permission_mode = "bypassPermissions",
      session_id = "sess",
      prompt = "p",
      status = "done",
      started = 1,
      events = {},
    }
    runner.runs.it1 = old
    local count = vim.tbl_count(runner.runs)
    local new_run, ierr = runner.iterate("it1", "more")
    check(new_run == nil and ierr ~= nil, "start: iterate onto a missing CLI fails")
    check(old.worktree == w.path and old.branch == w.branch, "start: the old run keeps its worktree and branch")
    check(vim.tbl_count(runner.runs) == count and no_live_records(), "start: the failed iteration leaves no record")

    -- resume onto a missing CLI: the run stays orphaned with its history
    old.status, old.finished, old.exit_code = "orphaned", 42, 1
    local rok, rerr = runner.resume("it1")
    check(rok == false and rerr ~= nil, "start: resume onto a missing CLI fails")
    check(old.status == "orphaned" and old.finished == 42, "start: the run stays orphaned, untouched")

    for _, r in ipairs({ blocker, queued, after, old }) do
      runner.discard(r.id)
    end
    check(not branch_exists("hangar/it1"), "start: cleanup removes the iterate fixture's branch")
    vim.fn.chdir(prev)
  end
end
