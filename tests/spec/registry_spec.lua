---adapter registry resolution, plus fail-fast on unsupported permission modes.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  local registry = require("hangar.adapters")
  check(registry.get("claude_code") ~= nil, "registry: resolves claude_code")
  check(registry.get("codex") ~= nil, "registry: resolves codex")
  check(registry.get("no_such_adapter") == nil, "registry: unknown adapter -> nil")
  check(select(2, registry.get("no_such_adapter")):find("available", 1, true) ~= nil, "registry: error lists available")
  check(
    vim.list_contains(registry.available(), "codex") and not vim.list_contains(registry.available(), "util"),
    "registry: available() lists adapters only"
  )

  -- Every shipped adapter satisfies hangar.Adapter. lua-language-server cannot
  -- enforce this — missing-fields only fires on a table literal, and an adapter
  -- assigns build_cmd/parse_line well after `local M = { name = ... }` — so the
  -- contract a fifth adapter has to meet is checked here instead.
  for _, name in ipairs(registry.available()) do
    local adapter, aerr = registry.get(name)
    check(
      adapter ~= nil,
      ("registry: %s implements the contract%s"):format(name, adapter and "" or ": " .. tostring(aerr))
    )
    if adapter then
      check(adapter.name == name, ("registry: %s reports its own name"):format(name))
      check(type(adapter.build_cmd) == "function", ("registry: %s has build_cmd"):format(name))
      check(type(adapter.parse_line) == "function", ("registry: %s has parse_line"):format(name))
      check(
        adapter.build_resume_cmd == nil or type(adapter.build_resume_cmd) == "function",
        ("registry: %s's optional build_resume_cmd is a function when present"):format(name)
      )
      check(
        adapter.unsupported_modes == nil or type(adapter.unsupported_modes) == "table",
        ("registry: %s's optional unsupported_modes is a table when present"):format(name)
      )
    end
  end

  -- ── unsupported permission modes fail fast at spawn ──────────────────
  do
    local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-safe-XXXXXX"))
    sh(repo, { "git", "init", "-b", "main" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    local runner = require("hangar.runner")
    local run, serr = runner.spawn("p", { permission_mode = "acceptEdits", adapter = "opencode" })
    check(
      run == nil and serr and serr ~= nil and serr:find("yolo", 1, true) ~= nil,
      "spawn: opencode --safe fails fast"
    )
    local wt_list = sh(repo, { "git", "worktree", "list" })
    check(select(2, wt_list:gsub("\n", "")) == 0, "spawn: fail-fast leaves no worktree behind")
    vim.fn.chdir(prev)
  end
end
