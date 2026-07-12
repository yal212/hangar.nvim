---Headless test harness. No plenary/busted — plain asserts + vim.wait.
---
---  Parser unit tests only (free, offline):
---    nvim --headless -l tests/run_tests.lua
---  Include the real end-to-end run (spawns `claude -p`, costs money):
---    XDG_DATA_HOME=$(mktemp -d) nvim --headless -l tests/run_tests.lua --integration

local script = arg[0]
local plugin_root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(plugin_root)

local failed = 0
local function check(cond, label)
  if cond then
    io.write("ok   " .. label .. "\n")
  else
    failed = failed + 1
    io.write("FAIL " .. label .. "\n")
  end
end

local function sh(cwd, cmd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert(res.code == 0, ("command failed: %s\n%s"):format(table.concat(cmd, " "), res.stderr))
  return vim.trim(res.stdout or "")
end

-- ── parser unit tests ────────────────────────────────────────────────
local adapter = require("hangar.adapters.claude_code")

local ev = adapter.parse_line('{"type":"system","subtype":"init","model":"claude-sonnet-5","session_id":"abc"}')
check(ev and ev.kind == "init" and ev.model == "claude-sonnet-5", "parses init event")

ev = adapter.parse_line(
  '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"},'
    .. '{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b.lua"}}]}}'
)
check(ev and ev.kind == "batch" and #ev.events == 2, "parses assistant batch")
check(ev and ev.events[1].kind == "text" and ev.events[1].text == "hi", "text block")
check(ev and ev.events[2].kind == "tool_use" and ev.events[2].tool == "Edit" and ev.events[2].summary == "/a/b.lua", "tool_use block + summary")

ev = adapter.parse_line(
  '{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"done"}],"is_error":false}]}}'
)
check(ev and ev.kind == "tool_result" and ev.text == "done" and ev.is_error == false, "parses tool_result")

ev = adapter.parse_line(
  '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.042,"num_turns":3,"duration_ms":9000,"result":"did it"}'
)
check(ev and ev.kind == "result" and ev.cost == 0.042 and ev.turns == 3 and not ev.is_error, "parses result stats")

check(adapter.parse_line('{"type":"some_future_event"}') == nil, "ignores unknown event types")
check(adapter.parse_line("not json at all") == nil, "ignores garbage lines")
check(adapter.parse_line("") == nil, "ignores blank lines")

local cmd = adapter.build_cmd({ prompt = "p", permission_mode = "bypassPermissions", model = "haiku" })
check(vim.list_contains(cmd, "stream-json") and vim.list_contains(cmd, "--verbose"), "build_cmd stream flags")
check(vim.list_contains(cmd, "bypassPermissions") and vim.list_contains(cmd, "haiku"), "build_cmd permission + model")

-- ── spawn arg parsing (via the public dispatcher surface) ────────────
local hangar = require("hangar")
hangar.setup({})

-- ── integration test (real claude run) ───────────────────────────────
if vim.list_contains(arg, "--integration") then
  io.write("\n-- integration: real claude -p run (this takes a minute) --\n")
  local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-test-XXXXXX")
  sh(repo, { "git", "init", "-b", "main" })
  sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
  sh(repo, { "git", "config", "user.name", "hangar-test" })
  local f = assert(io.open(repo .. "/README.md", "w"))
  f:write("# test repo\n")
  f:close()
  sh(repo, { "git", "add", "-A" })
  sh(repo, { "git", "commit", "-m", "init" })

  vim.fn.chdir(repo)
  hangar.setup({ model = "haiku" })

  local run = hangar.spawn(
    "Append the exact line 'hangar-test' to README.md. Make no other changes and do not commit.",
    { permission_mode = "bypassPermissions" }
  )
  check(run ~= nil, "spawn returns a run")
  if run then
    check(vim.uv.fs_stat(run.worktree) ~= nil, "worktree directory created")
    check(run.branch:match("^hangar/") ~= nil, "branch name")

    local done = vim.wait(300000, function()
      return run.status ~= "running"
    end, 250)
    check(done, "run finished within timeout")
    check(run.status == "done", "run status is done (got: " .. run.status .. (run.error and (", err: " .. run.error) or "") .. ")")
    check(type(run.cost) == "number", "cost parsed from result event")
    check(type(run.turns) == "number" and run.turns >= 1, "turn count parsed")
    check(#run.events > 0, "transcript events captured")

    local worktree = require("hangar.worktree")
    local files = worktree.changed_files(run)
    local touched = vim.tbl_map(function(x) return x.path end, files)
    check(vim.list_contains(touched, "README.md"), "README.md in changed files")

    local diff = sh(repo, { "git", "diff", run.base .. "..." .. run.branch })
    check(diff:find("hangar%-test") ~= nil, "branch diff contains the appended line")

    local runner = require("hangar.runner")
    local ok, err = runner.merge(run.id, "squash")
    check(ok, "squash merge succeeds" .. (err and (" (" .. err .. ")") or ""))
    local readme = sh(repo, { "cat", "README.md" })
    check(readme:find("hangar%-test") ~= nil, "merged README contains the line")

    local wt_list = sh(repo, { "git", "worktree", "list" })
    check(select(2, wt_list:gsub("\n", "")) == 0, "no orphan worktrees after merge")
    check(run.status == "merged", "run marked merged")
  end
end

io.write(failed == 0 and "\nALL PASS\n" or ("\n" .. failed .. " FAILURES\n"))
os.exit(failed == 0 and 0 or 1)
