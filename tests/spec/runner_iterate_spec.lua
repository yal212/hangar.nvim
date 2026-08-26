---runner: iterating on a finished run with follow-up feedback.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local runner = require("hangar.runner")
    check(
      runner._iterate_prompt({ prompt = "do x" }, "missed y") == "do x\n\nPrevious attempt feedback: missed y",
      "iterate: fresh prompt folds in feedback"
    )

    local tmp = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-iter-XXXXXX"))
    local plain = { build_cmd = function() end, parse_line = function() end }
    local resumable = vim.tbl_extend("force", plain, { build_resume_cmd = function() end })
    check(
      runner._iterate_mode({ session_id = "s", worktree = tmp }, resumable) == "resume",
      "iterate: resume with session + worktree + adapter support"
    )
    check(runner._iterate_mode({ session_id = "s", worktree = tmp }, plain) == "fresh", "iterate: fresh without resume")
    check(runner._iterate_mode({ worktree = tmp }, resumable) == "fresh", "iterate: fresh without a session id")
    check(
      runner._iterate_mode({ session_id = "s", worktree = tmp .. "/gone" }, resumable) == "fresh",
      "iterate: fresh when the worktree is gone"
    )

    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-iterrepo-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
    sh(repo, { "git", "config", "user.name", "hangar-test" })
    sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    local opts = { permission_mode = "bypassPermissions", adapter = "fake" }

    -- fresh path: no resumable session -> new worktree, feedback in the prompt
    local r1 = assert(runner.spawn("build a thing", vim.deepcopy(opts)))
    runner.kill(r1.id)
    vim.wait(10000, function()
      return r1.exit_code ~= nil
    end, 50)
    local r2, ierr = runner.iterate(r1.id, "make it better")
    check(r2 ~= nil, "iterate: fresh iteration spawns a run" .. (ierr and (" (" .. ierr .. ")") or ""))
    assert(r2)
    check(r1.group ~= nil and r2.group == r1.group, "iterate: runs share a lineage group")
    check(r1.attempt == 1 and r2.attempt == 2, "iterate: attempt numbering")
    check(r2.prompt:find("Previous attempt feedback", 1, true) ~= nil, "iterate: fresh prompt carries feedback")
    check(r1.worktree ~= nil and r2.worktree ~= r1.worktree, "iterate: fresh path keeps worktrees separate")

    -- resume path: the follow-up run takes over worktree + branch + session
    local r3 = assert(runner.spawn("task", { permission_mode = "bypassPermissions", adapter = "fakeresume" }))
    runner.kill(r3.id)
    vim.wait(10000, function()
      return r3.exit_code ~= nil
    end, 50)
    r3.session_id = "sess-3" -- the fake adapter emits no init event
    local wt3, br3 = r3.worktree, r3.branch
    local r4 = assert(runner.iterate(r3.id, "again"))
    check(r4.worktree == wt3 and r4.branch == br3, "iterate: resume run takes over worktree + branch")
    check(r3.worktree == nil and r3.branch == nil, "iterate: superseded run releases worktree + branch")
    check(r4.status == "running" and r4.session_id == "sess-3", "iterate: resume run is live with the session")
    check(r4.prompt == "again", "iterate: resume prompt is just the feedback")

    for _, r in ipairs({ r2, r4 }) do
      runner.kill(r.id)
      vim.wait(10000, function()
        return r.exit_code ~= nil
      end, 50)
    end
    for _, r in ipairs({ r1, r2, r3, r4 }) do
      runner.discard(r.id)
    end
    vim.fn.chdir(prev)
  end
end
