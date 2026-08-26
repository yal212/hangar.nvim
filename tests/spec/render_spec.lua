---Dashboard row building, driven directly rather than through a window.
---dashboard_spec covers the wired-up path; this covers the edges it cannot
---reach — the empty registry, the line -> run id map every key press resolves
---through, and the column formatters.
---@param harness table
return function(harness)
  local check = harness.check
  local runner = require("hangar.runner")
  local render = require("hangar.ui.render")

  local root = "/some/render/repo"

  ---A dashboard state backed by a scratch buffer instead of a float.
  ---@return hangar.DashboardState
  local function new_state(overrides)
    return vim.tbl_extend("force", {
      buf = vim.api.nvim_create_buf(false, true),
      win = nil,
      root = root,
      timer = nil,
      line_runs = {},
      files_cache = {},
      sort = "recent",
      hide_merged = false,
    }, overrides or {})
  end

  local function lines_of(state)
    return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  end

  -- empty registry: the onboarding line, and no footer to total
  local empty = new_state()
  render.render(empty, false)
  local text = table.concat(lines_of(empty), "\n")
  check(text:find("No runs yet.", 1, true) ~= nil, "render: an empty repo shows the spawn hint")
  check(text:find(":Hangar spawn --yolo <prompt>", 1, true) ~= nil, "render: the hint names the spawn command")
  check(text:find("running ·", 1, true) == nil, "render: no totals footer when there are no runs")
  check(next(empty.line_runs) == nil, "render: an empty repo maps no lines to runs")

  -- line_runs: the map run_under_cursor() resolves every dashboard key through
  runner.runs["r1"] = {
    id = "r1",
    root = root,
    adapter = "claude_code",
    status = "running",
    started = 100,
    events = {},
    prompt = "newest",
    model = "claude-sonnet-4-5-20250929",
  }
  runner.runs["r2"] = {
    id = "r2",
    root = root,
    adapter = "codex",
    status = "done",
    started = 90,
    finished = 190,
    events = {},
    prompt = "older",
    cost = 0.5,
    turns = 4,
  }
  runner.runs["r3"] =
    { id = "r3", root = "/elsewhere", status = "done", started = 95, events = {}, prompt = "other repo" }

  local state = new_state()
  render.render(state, false)
  local lines = lines_of(state)
  for lnum, id in pairs(state.line_runs) do
    check(lines[lnum]:find(id, 1, true) ~= nil, ("render: line %d maps to the run it displays (%s)"):format(lnum, id))
  end
  check(vim.tbl_count(state.line_runs) == 2, "render: only this repo's runs get rows")
  check(table.concat(lines, "\n"):find("other repo", 1, true) == nil, "render: another repo's runs are not rendered")

  -- column formatters
  local joined = table.concat(lines, "\n")
  check(joined:find("sonnet-4-5", 1, true) ~= nil, "render: short_model strips the claude- prefix and the date suffix")
  check(joined:find("claude-sonnet", 1, true) == nil, "render: the full model id is not rendered")
  check(joined:find(" claude ", 1, true) ~= nil, "render: claude_code shortens to claude in the adapter column")
  check(joined:find(" codex ", 1, true) ~= nil, "render: other adapters render under their own name")
  check(joined:find("$0.50", 1, true) ~= nil, "render: cost renders to two decimals")
  check(joined:find("total $0.50", 1, true) ~= nil, "render: the footer totals cost across runs")
  check(joined:find("1 running", 1, true) ~= nil, "render: the footer counts live runs")

  -- fmt_elapsed: a finished run freezes at finished - started; a live one grows
  check(joined:find("01:40", 1, true) ~= nil, "render: a finished run shows its frozen elapsed time (190-90 = 1m40s)")

  -- a run with no model, no cost and no turns renders placeholders, not nils
  runner.runs["r4"] =
    { id = "r4", root = root, status = "queued", started = 80, events = {}, prompt = "bare", model = vim.NIL }
  local bare = new_state()
  render.render(bare, false)
  local bare_row
  for lnum, id in pairs(bare.line_runs) do
    if id == "r4" then
      bare_row = lines_of(bare)[lnum]
    end
  end
  check(bare_row ~= nil, "render: a queued run still gets a row")
  check(bare_row and bare_row:find("-", 1, true) ~= nil, "render: absent model/cost/turns render as -")
  check(bare_row and not bare_row:find("vim.NIL", 1, true), "render: a vim.NIL model does not leak into the row")

  -- files_cache: honoured when refresh_files is false, recomputed when true.
  -- These runs have no worktree, so changed_files() returns {} and the cache
  -- would otherwise be 0 — a planted value proves which path ran.
  local cached = new_state({ files_cache = { r1 = 7, r2 = 7, r4 = 7 } })
  render.render(cached, false)
  check(table.concat(lines_of(cached), "\n"):find(" 7 ", 1, true) ~= nil, "render: a warm files cache is reused")
  render.render(cached, true)
  check(cached.files_cache.r1 == 0, "render: refresh_files recomputes the files column")

  -- hide_merged and the sort indicator only appear when they are in effect
  runner.runs["r5"] =
    { id = "r5", root = root, status = "merged", started = 70, events = {}, prompt = "already merged", cost = 1.0 }
  local filtered = new_state({ hide_merged = true })
  render.render(filtered, false)
  local ftext = table.concat(lines_of(filtered), "\n")
  check(ftext:find("already merged", 1, true) == nil, "render: hide_merged drops merged rows")
  check(ftext:find("[merged hidden]", 1, true) ~= nil, "render: hide_merged is announced in the footer")
  check(ftext:find("total $1.50", 1, true) ~= nil, "render: the footer totals over all runs, filtered or not")
  check(table.concat(lines_of(state), "\n"):find("sort:", 1, true) == nil, "render: the default sort is not announced")

  -- NEXT_SORT is the cycle the dashboard's `o` key walks
  check(
    render.NEXT_SORT.recent == "status" and render.NEXT_SORT.status == "cost" and render.NEXT_SORT.cost == "recent",
    "render: the sort cycle is recent -> status -> cost -> recent"
  )

  for _, id in ipairs({ "r1", "r2", "r3", "r4", "r5" }) do
    runner.runs[id] = nil
  end
  for _, s in ipairs({ empty, state, bare, cached, filtered }) do
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
end
