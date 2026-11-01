---runner: completion notifications and dashboard suppression.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local runner = require("hangar.runner")
    local hangar = require("hangar")
    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-notify-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
    sh(repo, { "git", "config", "user.name", "hangar-test" })
    sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })

    local next_id = 0
    local function mkrun()
      next_id = next_id + 1
      local id = "n" .. next_id
      local run = { id = id, status = "running", started = os.time() - 65, events = {}, worktree = repo, prompt = "p" }
      runner.runs[id] = run
      return run
    end

    local got
    hangar.setup({
      notify = function(r)
        got = r
      end,
    })
    local run = mkrun()
    runner._finish(run, 0)
    check(got == run and run.status == "done", "notify: function sink receives the run")

    hangar.setup({ notify = false })
    local called = false
    local orig_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function()
      called = true
    end
    run = mkrun()
    runner._finish(run, 1)
    vim.notify = orig_notify
    check(not called and run.status == "failed", "notify: false is silent")

    hangar.setup({ notify = true })
    local msg, lvl
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m, l)
      msg, lvl = m, l
    end
    run = mkrun()
    run.cost = 0.05
    runner._finish(run, 0)
    vim.notify = orig_notify
    check(
      msg and msg:find(run.id, 1, true) and msg:find("done", 1, true) and msg:find("$0.05", 1, true) ~= nil,
      "notify: message carries id, status, elapsed, cost"
    )
    check(lvl == vim.log.levels.INFO, "notify: done notifies at INFO")

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m)
      msg = m
    end
    run = mkrun()
    run.error = "a" .. ("修"):rep(50)
    runner._finish(run, 1)
    vim.notify = orig_notify
    check(
      msg and vim.endswith(msg, ": a" .. ("修"):rep(39)),
      "notify: a long multibyte error is cut on a character boundary"
    )

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m, l)
      msg, lvl = m, l
    end
    run = mkrun()
    run.error = "exploded"
    runner._finish(run, 1)
    vim.notify = orig_notify
    check(msg and msg:find("exploded", 1, true) and lvl == vim.log.levels.ERROR, "notify: failure carries the error")

    -- suppressed while the dashboard already shows the change live
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    require("hangar.ui.dashboard").open()
    check(require("hangar.ui.dashboard").is_open(), "notify: dashboard opens headless")
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function()
      called = true
    end
    called = false
    run = mkrun()
    runner._finish(run, 0)
    vim.notify = orig_notify
    check(not called, "notify: suppressed while dashboard is open")
    require("hangar.ui.dashboard").close()
    vim.fn.chdir(prev)

    for id in pairs(runner.runs) do
      if id:match("^n%d+$") then
        runner.runs[id] = nil
      end
    end
  end
end
