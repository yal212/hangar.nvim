---dashboard rendering: adapter column, footer, sort, filter.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local runner = require("hangar.runner")
    local dashboard = require("hangar.ui.dashboard")
    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-dash-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    local root = require("hangar.worktree").root()

    local function mk(id, fields)
      local run = vim.tbl_extend(
        "force",
        { id = id, root = root, adapter = "claude_code", started = 0, events = {}, prompt = "task " .. id },
        fields
      )
      runner.runs[id] = run
      return run
    end
    mk("a1", { status = "running", started = 100, model = "claude-haiku-4-5", cost = 0.10, turns = 2 })
    mk("a2", { status = "merged", started = 90, adapter = "codex", cost = 1.00 })
    mk("a3", { status = "done", started = 95, adapter = "opencode", cost = 0.05 })
    mk("g1", { status = "done", started = 80, prompt = "group task", group = "gX", attempt = 1 })
    mk("g2", { status = "failed", started = 81, prompt = "group task", group = "gX", attempt = 2 })

    dashboard.open()
    local function text()
      return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    end
    local t = text()
    check(t:find("claude ", 1, true) ~= nil and t:find("codex", 1, true) ~= nil, "dashboard: adapter column rendered")
    check(t:find("1 running", 1, true) ~= nil, "dashboard: footer counts running")
    check(t:find("total $1.15", 1, true) ~= nil, "dashboard: footer totals cost")
    check(t:find("2× group task", 1, true) ~= nil, "dashboard: group header intact")
    check(
      t:find("↳ attempt 1", 1, true) ~= nil and t:find("↳ attempt 2", 1, true) ~= nil,
      "dashboard: group members render"
    )

    dashboard.toggle_merged()
    t = text()
    check(t:find("a2", 1, true) == nil, "dashboard: filter hides merged runs")
    check(t:find("merged hidden", 1, true) ~= nil, "dashboard: filter indicator shown")
    dashboard.toggle_merged()

    dashboard.cycle_sort() -- status
    t = text()
    check(t:find("sort: status", 1, true) ~= nil, "dashboard: sort indicator shown")
    check((t:find("a1", 1, true)) < (t:find("a2", 1, true)), "dashboard: status sort puts live work first")
    dashboard.cycle_sort() -- cost
    t = text()
    check((t:find("a2", 1, true)) < (t:find("a3", 1, true)), "dashboard: cost sort descends")
    check(t:find("2× group task", 1, true) ~= nil, "dashboard: groups stay blocks under sort")
    dashboard.cycle_sort() -- back to recent

    -- the window fits its content, key hints included, and grows with new runs
    local win = vim.api.nvim_get_current_win()
    local function fits()
      return vim.api.nvim_win_get_height(win) >= vim.api.nvim_buf_line_count(0)
    end
    local function line_of(id)
      for lnum, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if l:find("%s" .. id .. "%s") then
          return lnum
        end
      end
    end
    check(fits(), "dashboard: the window shows every line, key hints included")
    local rows_before = vim.api.nvim_buf_line_count(0)

    -- a newer run renders above the cursor's row and shifts it down; the
    -- cursor must follow its run, or K would kill a different one
    vim.api.nvim_win_set_cursor(win, { assert(line_of("a3")), 0 })
    mk("a4", { status = "running", started = 200 })
    dashboard.render(false)
    check(vim.api.nvim_buf_line_count(0) > rows_before and fits(), "dashboard: the window grows when a run is added")
    check(
      vim.api.nvim_win_get_cursor(win)[1] == line_of("a3"),
      "dashboard: the cursor stays on its run when the rows shift"
    )
    dashboard.close()

    for _, id in ipairs({ "a1", "a2", "a3", "a4", "g1", "g2" }) do
      runner.runs[id] = nil
    end
    vim.fn.chdir(prev)
  end
end
