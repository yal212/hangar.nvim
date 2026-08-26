---Run registry persistence: atomic writes and load-time status reconciliation.
---@param harness table
return function(harness)
  local check = harness.check
  local store = require("hangar.store")

  ---A run table with the fields hangar.Run requires, so the specs below can
  ---name only the ones they actually care about.
  ---@param fields table
  ---@return hangar.Run
  local function run(fields)
    return vim.tbl_extend("force", {
      prompt = "test prompt",
      adapter = "fake",
      permission_mode = "acceptEdits",
      root = "/tmp/hangar-store-spec",
      events = {},
    }, fields)
  end

  do
    -- run_tests.lua points the whole process at one scratch state dir; repoint it
    -- per-case and put it back, or later specs write somewhere unexpected.
    local original_dir = vim.fn.fnamemodify(store.path(), ":h:h")
    local dir = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-store-XXXXXX"))
    store.set_state_dir(dir)
    local path = store.path()

    -- round trip
    store.save({ a = run({ id = "a", status = "done", started = 1 }) })
    local read = store.read()
    check(read ~= nil and read.a ~= nil and read.a.status == "done", "store: save/read round trip")
    check(vim.uv.fs_stat(path .. ".tmp") == nil, "store: no .tmp left behind after a successful save")

    -- an unwritable state dir must not raise, and must not damage what is there
    local before = store.read()
    vim.uv.fs_chmod(vim.fn.fnamemodify(path, ":h"), tonumber("500", 8))
    local ok = pcall(store.save, { b = run({ id = "b", status = "running", started = 2 }) })
    vim.uv.fs_chmod(vim.fn.fnamemodify(path, ":h"), tonumber("700", 8))
    check(ok, "store: save into an unwritable dir does not raise")
    local after = store.read()
    check(
      after ~= nil and after.a ~= nil and after.b == nil and vim.deep_equal(before, after),
      "store: a failed write leaves the previous registry intact"
    )
    check(vim.uv.fs_stat(path .. ".tmp") == nil, "store: no .tmp left behind after a failed save")

    -- load() reconciles statuses a previous nvim session left behind
    store.save({
      live = run({ id = "live", status = "running", pid = vim.uv.os_getpid(), started = 1 }),
      dead = run({ id = "dead", status = "running", pid = 2 ^ 30, started = 2 }),
      parked = run({ id = "parked", status = "queued", started = 3 }),
      finished = run({ id = "finished", status = "done", started = 4 }),
    })
    local loaded = store.load()
    check(loaded.live.status == "detached", "store: load classifies a live pid as detached")
    check(loaded.dead.status == "orphaned", "store: load classifies a dead pid as orphaned")
    check(
      loaded.parked.status == "killed" and loaded.parked.error ~= nil,
      "store: load kills a queued run that never started, with a reason"
    )
    check(loaded.finished.status == "done", "store: load leaves finished runs alone")

    -- corrupt / absent registries read as "no history", never as an error
    local f = assert(io.open(path, "w"))
    f:write("{not json")
    f:close()
    check(store.read() == nil, "store: corrupt registry reads as nil")
    os.remove(path)
    check(store.read() == nil, "store: absent registry reads as nil")
    check(vim.tbl_isempty(store.load()), "store: load with no registry is empty")

    store.set_state_dir(original_dir)
  end
end
