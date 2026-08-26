---Shared picker data and the action table both frontends are driven from.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  local pickers = require("hangar.pickers")
  local runner = require("hangar.runner")

  local repo = harness.git_repo("pickers")
  sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
  local prev = assert(vim.uv.cwd())
  vim.fn.chdir(repo)
  local root = require("hangar.worktree").root()

  -- action table: both frontends iterate this, so its shape is the contract
  check(#pickers.actions == 4, "pickers: four actions exposed")
  local defaults, names = 0, {}
  for _, a in ipairs(pickers.actions) do
    names[#names + 1] = a.name
    if a.default then
      defaults = defaults + 1
    end
    check(type(a.run) == "function", "pickers: " .. a.name .. " has a run function")
    check(type(a.fzf) == "string" and type(a.telescope) == "string", "pickers: " .. a.name .. " binds both frontends")
  end
  check(table.concat(names, ",") == "transcript,review,iterate,discard", "pickers: actions are in menu order")
  check(defaults == 1, "pickers: exactly one action is the default")

  -- entries(): one display line per run in this repo, newest first
  runner.runs["p1"] = {
    id = "p1",
    root = root,
    status = "done",
    started = 1,
    events = {},
    prompt = "fix   the\nbug",
    cost = 0.25,
    turns = 3,
  }
  runner.runs["p2"] = { id = "p2", root = root, status = "running", started = 2, events = {}, prompt = "other task" }
  runner.runs["p3"] = { id = "p3", root = "/some/other/repo", status = "done", started = 3, events = {}, prompt = "x" }

  local entries, err = pickers.entries()
  check(entries and not err, "pickers: entries() succeeds inside a repo")
  check(entries and #entries == 2, "pickers: entries() covers this repo only")
  local first = entries and entries[1]
  check(first and first.run.id == "p2", "pickers: entries() newest first")
  local done = entries and (entries[1].run.id == "p1" and entries[1] or entries[2])
  check(done and done.display:find("p1", 1, true) ~= nil, "pickers: display carries the run id")
  check(done and done.display:find("fix the bug", 1, true) ~= nil, "pickers: display collapses prompt whitespace")
  check(done and done.display:find("$0.25", 1, true) ~= nil, "pickers: display carries cost")
  check(done and done.display:find("3 turns", 1, true) ~= nil, "pickers: display carries turns")

  for _, id in ipairs({ "p1", "p2", "p3" }) do
    runner.runs[id] = nil
  end
  vim.fn.chdir(prev)

  -- outside a repo, entries() reports why rather than returning an empty list
  local tmp = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-norepo-XXXXXX"))
  vim.fn.chdir(tmp)
  local none, nerr = pickers.entries()
  check(none == nil and type(nerr) == "string", "pickers: entries() errors outside a git repo")
  vim.fn.chdir(prev)
end
