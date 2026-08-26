---End-to-end runs against the real agent CLIs. Spawns real processes and
---costs money, so this never runs in CI — see CONTRIBUTING.md.
---@param harness table
---@param names string[] adapter specs, e.g. { "codex", "claude_code:safe" }
return function(harness, names)
  local check, sh = harness.check, harness.sh
  local hangar = require("hangar")

  ---Fast/cheap model per adapter for e2e runs; nil = the CLI's default.
  local E2E_MODEL = { claude_code = "haiku" }

  ---@param spec string adapter name, optionally with a ":safe" suffix to run acceptEdits
  local function run_e2e(spec)
    local adapter_name, mode = spec:match("^([^:]+):?(.*)$")
    local permission = mode == "safe" and "acceptEdits" or "bypassPermissions"
    io.write(("\n-- integration: real %s run (this takes a minute) --\n"):format(spec))
    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-test-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
    sh(repo, { "git", "config", "user.name", "hangar-test" })
    local f = assert(io.open(repo .. "/README.md", "w"))
    f:write("# test repo\n")
    f:close()
    sh(repo, { "git", "add", "-A" })
    sh(repo, { "git", "commit", "-m", "init" })

    vim.fn.chdir(repo)

    local run =
      hangar.spawn("Append the exact line 'hangar-test' to README.md. Make no other changes and do not commit.", {
        permission_mode = permission,
        adapter = adapter_name,
        model = E2E_MODEL[adapter_name],
      })
    local t = spec .. ": "
    check(run ~= nil, t .. "spawn returns a run")
    if not run then
      return
    end
    check(run.adapter == adapter_name, t .. "run records adapter")
    check(vim.uv.fs_stat(run.worktree) ~= nil, t .. "worktree directory created")
    check(run.branch:match("^hangar/") ~= nil, t .. "branch name")

    local done = vim.wait(300000, function()
      return run.status ~= "running"
    end, 250)
    check(done, t .. "run finished within timeout")
    check(
      run.status == "done",
      t .. "run status is done (got: " .. run.status .. (run.error and (", err: " .. run.error) or "") .. ")"
    )
    check(#run.events > 0, t .. "transcript events captured")
    if adapter_name == "claude_code" then
      check(type(run.cost) == "number", t .. "cost parsed from result event")
      check(type(run.turns) == "number" and run.turns >= 1, t .. "turn count parsed")
    end

    -- regression: the agent must never write into the main tree (worktree escape)
    local root_status = sh(repo, { "git", "status", "--porcelain" })
    check(root_status == "", t .. "main repo working tree untouched by the run")

    local worktree = require("hangar.worktree")
    local files = worktree.changed_files(run)
    local touched = vim.tbl_map(function(x)
      return x.path
    end, files)
    check(vim.list_contains(touched, "README.md"), t .. "README.md in changed files")

    local diff = sh(repo, { "git", "diff", run.base .. "..." .. run.branch })
    check(diff:find("hangar%-test") ~= nil, t .. "branch diff contains the appended line")

    local runner = require("hangar.runner")
    local ok, err = runner.merge(run.id, "squash")
    check(ok, t .. "squash merge succeeds" .. (err and (" (" .. err .. ")") or ""))
    local readme = sh(repo, { "cat", "README.md" })
    check(readme:find("hangar%-test") ~= nil, t .. "merged README contains the line")

    local wt_list = sh(repo, { "git", "worktree", "list" })
    check(select(2, wt_list:gsub("\n", "")) == 0, t .. "no orphan worktrees after merge")
    check(run.status == "merged", t .. "run marked merged")
  end

  for _, name in ipairs(names) do
    run_e2e(name)
  end
end
