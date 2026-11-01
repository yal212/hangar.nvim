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

    -- the spawn notification for a queued run has no branch to name yet
    local said
    local orig_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m)
      said = m
    end
    local api_run = hangar.spawn("via the api", vim.deepcopy(opts))
    vim.notify = orig_notify
    check(
      said ~= nil and said:find("queued", 1, true) ~= nil and said:find("nil", 1, true) == nil,
      "queue: a queued spawn says it is queued (" .. tostring(said) .. ")"
    )
    if api_run and api_run.id then
      runner.kill(api_run.id)
      runner.discard(api_run.id)
    end

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

    -- `started` has one-second resolution: runs queued within the same second
    -- must still leave the queue in spawn order
    local blocker = assert(runner.spawn("blocker", vim.deepcopy(opts)))
    local fleet = {}
    for i = 1, 5 do
      fleet[i] = assert(runner.spawn("same second " .. i, vim.deepcopy(opts)))
    end
    for i = 2, 5 do
      fleet[i].started = fleet[1].started -- force the tie even across a second boundary
    end
    local order_ok = true
    local current = blocker
    for i = 1, 5 do
      runner.kill(current.id)
      vim.wait(10000, function()
        return fleet[i].status ~= "queued"
      end, 50)
      for j = i + 1, 5 do
        order_ok = order_ok and fleet[j].status == "queued"
      end
      order_ok = order_ok and fleet[i].status == "running"
      current = fleet[i]
    end
    check(order_ok, "queue: same-second spawns start oldest-first")
    runner.kill(current.id)
    vim.wait(10000, function()
      return current.exit_code ~= nil
    end, 50)
    runner.discard(blocker.id)
    for _, r in ipairs(fleet) do
      runner.discard(r.id)
    end

    hangar.config.max_concurrent = nil
    vim.fn.chdir(prev)
  end
end
