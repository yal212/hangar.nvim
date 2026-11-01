---runner: every public entry point loads the persisted registry before acting
---on it, so a fresh nvim session sees the runs a previous one left behind.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  local runner = require("hangar.runner")
  local store = require("hangar.store")

  do
    local original_dir = vim.fn.fnamemodify(store.path(), ":h:h")
    local snapshot = vim.deepcopy(runner.runs)
    local repo = harness.git_repo("load")
    sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })

    ---A persisted run with the fields hangar.Run requires.
    local function persisted(fields)
      return vim.tbl_extend("force", {
        prompt = "p",
        adapter = "fake",
        permission_mode = "acceptEdits",
        root = repo,
        events = {},
        started = 1,
      }, fields)
    end

    ---Write `runs` as the registry and forget the in-memory one, as if nvim
    ---had just started.
    local function fresh_session(runs)
      store.set_state_dir(assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-load-XXXXXX")))
      store.save(runs)
      runner._unload()
    end

    -- :Hangar clean before anything else loaded the registry used to save an
    -- empty one, wiping every repo's runs
    fresh_session({
      other = persisted({ id = "other", root = "/elsewhere/repo", status = "done" }),
      mine = persisted({ id = "mine", status = "done" }),
    })
    local count = runner.clean(repo)
    local after = store.read() or {}
    check(after.other ~= nil, "load: clean in a fresh session keeps other repos' runs")
    check(count == 1 and after.mine == nil, "load: clean in a fresh session cleans this repo's persisted run")

    -- :Hangar kill <id> typed without <Tab> completion
    local proc = vim.system({ "sleep", "30" })
    fresh_session({ det = persisted({ id = "det", status = "running", pid = proc.pid }) })
    local ok, err = runner.kill("det")
    check(ok == true and runner.runs.det.status == "killed", "load: kill in a fresh session stops a detached run")
    check(err == nil, "load: kill in a fresh session finds the persisted run")
    local res = proc:wait(5000)
    check(res.signal == 15, "load: kill signalled the detached process")

    fresh_session({ d1 = persisted({ id = "d1", status = "done" }) })
    check(runner.discard("d1") == true, "load: discard in a fresh session finds the persisted run")

    local live = vim.uv.os_getpid() -- alive for the whole test: loads as detached
    fresh_session({ m1 = persisted({ id = "m1", status = "running", pid = live }) })
    local _, merr = runner.merge("m1")
    check(merr ~= nil and merr:find("no such run", 1, true) == nil, "load: merge in a fresh session finds the run")
    fresh_session({ m2 = persisted({ id = "m2", status = "running", pid = live }) })
    local _, rerr = runner.rebase_and_merge("m2")
    check(
      rerr ~= nil and rerr:find("no such run", 1, true) == nil,
      "load: rebase_and_merge in a fresh session finds the run"
    )

    -- restore the registry the other specs see: loaded, holding what it held before
    fresh_session({})
    runner.load()
    for id, run in pairs(snapshot) do
      runner.runs[id] = run
    end
    store.set_state_dir(original_dir)
  end
end
