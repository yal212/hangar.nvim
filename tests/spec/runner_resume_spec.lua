---runner: detached run classification and resume preconditions.
---@param harness table
return function(harness)
  local check = harness.check
  do
    local runner = require("hangar.runner")
    local root = "/detach/test"

    local proc = vim.system({ "sleep", "30" })
    check(
      require("hangar.store").classify_loaded({ pid = proc.pid }) == "detached",
      "detached: live pid classifies as detached"
    )
    proc:kill(9)
    proc:wait()
    check(
      require("hangar.store").classify_loaded({ pid = proc.pid }) == "orphaned",
      "detached: dead pid classifies as orphaned"
    )
    check(require("hangar.store").classify_loaded({}) == "orphaned", "detached: missing pid classifies as orphaned")

    -- a watched detached run whose process dies flips to orphaned via list()
    local proc2 = vim.system({ "sleep", "30" })
    local run = { id = "d1", root = root, status = "detached", pid = proc2.pid, started = 1, events = {}, prompt = "p" }
    runner.runs.d1 = run
    runner.list(root)
    check(run.status == "detached", "detached: stays detached while the process lives")
    proc2:kill(9)
    proc2:wait()
    runner.list(root)
    check(run.status == "orphaned" and run.finished ~= nil, "detached: dead process flips to orphaned on list()")

    local proc3 = vim.system({ "sleep", "30" })
    run = { id = "d2", root = root, status = "detached", pid = proc3.pid, started = 2, events = {}, prompt = "p" }
    runner.runs.d2 = run
    local mok, merr = runner.merge("d2")
    check(mok == false and merr ~= nil and merr:find("running", 1, true) ~= nil, "detached: merge blocked while alive")
    local dok, derr = runner.discard("d2")
    check(dok == false and derr ~= nil and derr:find("kill", 1, true) ~= nil, "detached: discard blocked while alive")
    check(runner.kill("d2") == true and run.status == "killed", "detached: kill signals the pid directly")
    proc3:wait()

    local rok, rerr = runner.resume("d2")
    check(rok == false and rerr ~= nil and rerr:find("killed", 1, true) ~= nil, "resume: only orphaned runs resume")
    run =
      { id = "d3", root = root, status = "orphaned", adapter = "claude_code", started = 3, events = {}, prompt = "p" }
    runner.runs.d3 = run
    rok, rerr = runner.resume("d3")
    check(
      rok == false and rerr ~= nil and rerr:find("session id", 1, true) ~= nil,
      "resume: needs a captured session id"
    )
    run.session_id = "sess"
    run.worktree = "/no/such/dir"
    rok, rerr = runner.resume("d3")
    check(rok == false and rerr ~= nil and rerr:find("worktree", 1, true) ~= nil, "resume: needs the worktree on disk")
    run = { id = "d4", root = root, status = "orphaned", adapter = "fake", started = 4, events = {}, prompt = "p" }
    runner.runs.d4 = run
    rok, rerr = runner.resume("d4")
    check(
      rok == false and rerr ~= nil and rerr:find("does not support", 1, true) ~= nil,
      "resume: adapter without resume errors"
    )

    for _, id in ipairs({ "d1", "d2", "d3", "d4" }) do
      runner.runs[id] = nil
    end
  end
end
