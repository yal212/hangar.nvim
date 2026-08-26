---statusline component: counts, caching, and refresh.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-status-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    local status = require("hangar.status")
    local runner = require("hangar.runner")
    local root = require("hangar.worktree").root()

    check(status.text() == "", "status: empty string with no runs")

    runner.runs["s1"] = { id = "s1", root = root, status = "running", started = 1, events = {} }
    runner.runs["s2"] = { id = "s2", root = root, status = "running", started = 2, events = {} }
    runner.runs["s3"] = { id = "s3", root = root, status = "done", started = 3, events = {} }
    runner.runs["s4"] = { id = "s4", root = "/some/other/repo", status = "failed", started = 4, events = {} }
    vim.api.nvim_exec_autocmds("User", { pattern = "HangarRunUpdate", data = { id = "s1" } })

    check(status.text() == "hangar 2 ● 1 ✓", "status: counts running + awaiting review for this repo only")
    local c = status.counts()
    check(c and c.running == 2 and c.done == 1 and c.failed == 0, "status: counts table")

    runner.runs["s1"].status = "failed"
    check(status.text() == "hangar 2 ● 1 ✓", "status: cached until a run update fires")
    vim.api.nvim_exec_autocmds("User", { pattern = "HangarRunUpdate", data = { id = "s1" } })
    check(status.text() == "hangar 1 ● 1 ✓ 1 ✗", "status: refreshes on HangarRunUpdate")

    for _, id in ipairs({ "s1", "s2", "s3", "s4" }) do
      runner.runs[id] = nil
    end
    vim.api.nvim_exec_autocmds("User", { pattern = "HangarRunUpdate", data = {} })
    vim.fn.chdir(prev)
  end
end
