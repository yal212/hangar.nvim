---runner: max_concurrent cap and the spawn queue.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local runner = require("hangar.runner")
    local hangar = require("hangar")
    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-queue-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
    sh(repo, { "git", "config", "user.name", "hangar-test" })
    sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)

    hangar.setup({ max_concurrent = 1, notify = false })
    local opts = { permission_mode = "bypassPermissions", adapter = "fake" }
    local r1 = assert(runner.spawn("first", vim.deepcopy(opts)))
    local r2 = assert(runner.spawn("second", vim.deepcopy(opts)))
    local r3 = assert(runner.spawn("third", vim.deepcopy(opts)))
    check(r1.status == "running" and r1.worktree ~= nil and r1.pid ~= nil, "queue: first run starts under the cap")
    check(r2.status == "queued" and r2.worktree == nil and r2.pid == nil, "queue: overflow spawn parks as queued")
    check(r3.status == "queued", "queue: further spawns keep queueing")
    check(require("hangar.status").text():find("◌", 1, true) ~= nil, "queue: statusline shows queued count")

    local ok = runner.kill(r3.id)
    check(ok and r3.status == "killed", "queue: queued run can be killed without a job")
    local dok = runner.discard(r3.id)
    check(dok and runner.get(r3.id) == nil, "queue: killed queued run can be discarded")

    local mok, merr = runner.merge(r2.id)
    check(
      mok == false and merr ~= nil and merr:find("not started", 1, true) ~= nil,
      "queue: merge rejects a queued run"
    )

    runner.kill(r1.id)
    local promoted = vim.wait(10000, function()
      return r2.status == "running"
    end, 50)
    check(promoted and r2.worktree ~= nil and r2.pid ~= nil, "queue: freeing a slot promotes the oldest queued run")
    check(r1.status == "killed", "queue: killed run stays killed")

    runner.kill(r2.id)
    vim.wait(10000, function()
      return r2.exit_code ~= nil
    end, 50)
    runner.discard(r1.id)
    runner.discard(r2.id)
    hangar.config.max_concurrent = nil
    vim.fn.chdir(prev)
  end
end
