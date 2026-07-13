---Headless test harness. No plenary/busted — plain asserts + vim.wait.
---
---  Parser unit tests only (free, offline):
---    nvim --headless -l tests/run_tests.lua
---  Include real end-to-end runs (spawns actual agent CLIs, costs money):
---    XDG_DATA_HOME=$(mktemp -d) nvim --headless -l tests/run_tests.lua --integration [adapter ...]
---  Adapter names default to claude_code; e.g. `--integration codex opencode`.
---  Append ":safe" to an adapter name to run it with acceptEdits, e.g. `claude_code:safe`.

local script = arg[0]
local plugin_root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(plugin_root)

-- never touch the user's real run registry, even without XDG_DATA_HOME set
require("hangar.runner")._set_state_dir(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-state-XXXXXX"))

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
check(
  ev and ev.events[2].kind == "tool_use" and ev.events[2].tool == "Edit" and ev.events[2].summary == "/a/b.lua",
  "tool_use block + summary"
)

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
cmd = adapter.build_cmd({ prompt = "p", permission_mode = "acceptEdits" })
check(vim.list_contains(cmd, "--permission-mode") and vim.list_contains(cmd, "acceptEdits"), "safe -> acceptEdits")
check(not vim.list_contains(cmd, "--no-session-persistence"), "build_cmd keeps sessions resumable")
local rcmd = adapter.build_resume_cmd({ prompt = "go on", session_id = "sess-1", permission_mode = "acceptEdits" })
check(
  vim.list_contains(rcmd, "--resume") and vim.list_contains(rcmd, "sess-1") and vim.list_contains(rcmd, "go on"),
  "resume cmd: --resume + session + prompt"
)

-- ── codex adapter (canned lines captured from a real `codex exec --json` run) ──
local codex = require("hangar.adapters.codex")

ev = codex.parse_line('{"type":"thread.started","thread_id":"019f593c-b70e-7e50-8fe1-9adc2a2deb22"}')
check(
  ev and ev.kind == "init" and ev.session_id == "019f593c-b70e-7e50-8fe1-9adc2a2deb22",
  "codex: init from thread.started"
)

check(codex.parse_line('{"type":"turn.started"}') == nil, "codex: turn.started ignored")

ev = codex.parse_line('{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"hello hangar"}}')
check(ev and ev.kind == "text" and ev.text == "hello hangar", "codex: agent_message -> text")

ev = codex.parse_line(
  '{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc \\"printf hi > probe.txt\\"","aggregated_output":"","exit_code":null,"status":"in_progress"}}'
)
check(
  ev and ev.kind == "tool_use" and ev.tool == "shell" and ev.summary:find("printf", 1, true),
  "codex: command start -> tool_use"
)

ev = codex.parse_line(
  '{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"c","aggregated_output":"       3 probe.txt\\n","exit_code":0,"status":"completed"}}'
)
check(
  ev and ev.kind == "tool_result" and ev.is_error == false and ev.text:find("probe.txt", 1, true),
  "codex: command done -> tool_result"
)

ev = codex.parse_line(
  '{"type":"item.completed","item":{"id":"i","type":"command_execution","command":"c","aggregated_output":"boom","exit_code":1,"status":"failed"}}'
)
check(ev and ev.kind == "tool_result" and ev.is_error == true, "codex: failed command -> tool_result error")

ev = codex.parse_line(
  '{"type":"item.completed","item":{"id":"i","type":"file_change","changes":[{"path":"/a/b.lua","kind":"update"}],"status":"completed"}}'
)
check(
  ev and ev.kind == "tool_use" and ev.tool == "edit" and ev.summary:find("b.lua", 1, true),
  "codex: file_change -> tool_use"
)

ev = codex.parse_line(
  '{"type":"turn.completed","usage":{"input_tokens":12131,"cached_input_tokens":1920,"output_tokens":7}}'
)
check(
  ev and ev.kind == "result" and ev.is_error == false and ev.cost == nil,
  "codex: turn.completed -> result, no cost"
)

ev = codex.parse_line('{"type":"turn.failed","error":{"message":"rate limited"}}')
check(
  ev and ev.kind == "result" and ev.is_error == true and ev.text == "rate limited",
  "codex: turn.failed -> error result"
)

check(codex.parse_line('{"type":"some_future_event"}') == nil, "codex: ignores unknown event types")
check(codex.parse_line("not json") == nil, "codex: ignores garbage lines")

cmd = codex.build_cmd({ prompt = "p", permission_mode = "bypassPermissions", model = "gpt-5.3-codex" })
check(cmd[1] == "codex" and cmd[2] == "exec" and vim.list_contains(cmd, "--json"), "codex: build_cmd shape")
check(vim.list_contains(cmd, "--dangerously-bypass-approvals-and-sandbox"), "codex: yolo -> bypass sandbox")
check(vim.list_contains(cmd, "gpt-5.3-codex") and cmd[#cmd] == "p", "codex: model flag + prompt last")
cmd = codex.build_cmd({ prompt = "p", permission_mode = "acceptEdits" })
check(vim.list_contains(cmd, "workspace-write"), "codex: safe -> workspace-write sandbox")
check(not vim.list_contains(cmd, "--ephemeral"), "codex: threads persist for resume")
rcmd = codex.build_resume_cmd({ prompt = "go on", session_id = "t-1", permission_mode = "bypassPermissions" })
check(
  rcmd[2] == "exec" and rcmd[3] == "resume" and rcmd[4] == "t-1" and rcmd[#rcmd] == "go on",
  "codex: resume cmd shape"
)

-- ── gemini adapter (canned lines per the CLI's StreamJsonFormatter schema) ──
local gemini = require("hangar.adapters.gemini")

ev = gemini.parse_line('{"type":"init","timestamp":"2026-07-13T10:00:00Z","session_id":"s-1","model":"gemini-2.5-pro"}')
check(ev and ev.kind == "init" and ev.model == "gemini-2.5-pro" and ev.session_id == "s-1", "gemini: init event")

check(gemini.parse_line('{"type":"message","role":"user","content":"the prompt"}') == nil, "gemini: user echo skipped")

ev = gemini.parse_line('{"type":"message","role":"assistant","content":"hel","delta":true}')
check(ev and ev.kind == "text" and ev.text == "hel" and ev.delta == true, "gemini: assistant delta -> text")

ev =
  gemini.parse_line('{"type":"tool_use","tool_name":"write_file","tool_id":"t1","parameters":{"file_path":"/a/b.md"}}')
check(
  ev and ev.kind == "tool_use" and ev.tool == "write_file" and ev.summary == "/a/b.md",
  "gemini: tool_use + summary"
)

ev = gemini.parse_line('{"type":"tool_result","tool_id":"t1","status":"success","output":"wrote file"}')
check(ev and ev.kind == "tool_result" and ev.is_error == false and ev.text == "wrote file", "gemini: tool_result ok")

ev = gemini.parse_line(
  '{"type":"tool_result","tool_id":"t2","status":"error","output":"","error":{"type":"TOOL_EXECUTION_ERROR","message":"denied"}}'
)
check(ev and ev.kind == "tool_result" and ev.is_error == true and ev.text == "denied", "gemini: tool_result error")

ev = gemini.parse_line(
  '{"type":"result","status":"success","stats":{"total_tokens":100,"duration_ms":4200,"tool_calls":2}}'
)
check(
  ev and ev.kind == "result" and ev.is_error == false and ev.duration_ms == 4200 and ev.cost == nil,
  "gemini: success result, no cost"
)

ev = gemini.parse_line(
  '{"type":"result","status":"error","error":{"type":"FatalAuthenticationError","message":"auth failed"},"stats":{}}'
)
check(ev and ev.kind == "result" and ev.is_error == true and ev.text == "auth failed", "gemini: error result")

check(gemini.parse_line('{"type":"some_future_event"}') == nil, "gemini: ignores unknown event types")
check(gemini.parse_line("garbage") == nil, "gemini: ignores garbage lines")

cmd = gemini.build_cmd({ prompt = "p", permission_mode = "bypassPermissions", model = "gemini-2.5-flash" })
check(
  cmd[1] == "gemini" and vim.list_contains(cmd, "stream-json") and vim.list_contains(cmd, "--skip-trust"),
  "gemini: build_cmd shape"
)
check(vim.list_contains(cmd, "yolo") and vim.list_contains(cmd, "gemini-2.5-flash"), "gemini: yolo approval + model")
cmd = gemini.build_cmd({ prompt = "p", permission_mode = "acceptEdits" })
check(vim.list_contains(cmd, "auto_edit"), "gemini: safe -> auto_edit approval")

-- ── opencode adapter (canned lines captured from a real `opencode run --format json` run) ──
local opencode = require("hangar.adapters.opencode")

ev = opencode.parse_line(
  '{"type":"step_start","timestamp":1783909220823,"sessionID":"ses_0a6b","part":{"id":"prt_1","type":"step-start"}}'
)
check(ev and ev.kind == "init" and ev.session_id == "ses_0a6b", "opencode: step_start -> init")

ev = opencode.parse_line('{"type":"text","sessionID":"ses_0a6b","part":{"type":"text","text":"hello hangar"}}')
check(ev and ev.kind == "text" and ev.text == "hello hangar", "opencode: text part")

ev = opencode.parse_line(
  '{"type":"tool_use","sessionID":"s","part":{"type":"tool","tool":"apply_patch","callID":"c1","state":{"status":"completed","input":{"patchText":"*** Add File: probe.txt"},"output":"Success. Updated the following files:\\nA probe.txt","title":"Success"}}}'
)
check(ev and ev.kind == "batch" and #ev.events == 2, "opencode: tool_use -> batch")
check(
  ev
    and ev.events[1].kind == "tool_use"
    and ev.events[1].tool == "apply_patch"
    and ev.events[1].summary:find("Add File", 1, true),
  "opencode: tool_use summary from input"
)
check(
  ev
    and ev.events[2].kind == "tool_result"
    and ev.events[2].is_error == false
    and ev.events[2].text:find("probe.txt", 1, true),
  "opencode: tool output -> tool_result"
)

ev = opencode.parse_line(
  '{"type":"tool_use","part":{"type":"tool","tool":"bash","state":{"status":"error","input":{"command":"rm -rf /"},"output":"denied"}}}'
)
check(ev and ev.events[2].is_error == true, "opencode: errored tool -> tool_result error")

ev = opencode.parse_line(
  '{"type":"step_finish","part":{"type":"step-finish","reason":"stop","tokens":{"total":10850},"cost":0.0123}}'
)
check(
  ev and ev.kind == "result" and ev.partial == true and ev.cost == 0.0123,
  "opencode: step_finish -> partial result with cost"
)

check(opencode.parse_line('{"type":"some_future_event"}') == nil, "opencode: ignores unknown event types")
check(opencode.parse_line("garbage") == nil, "opencode: ignores garbage lines")

cmd = opencode.build_cmd({
  prompt = "p",
  permission_mode = "bypassPermissions",
  model = "anthropic/claude-haiku-4-5",
  cwd = "/wt/path",
})
check(cmd[1] == "opencode" and cmd[2] == "run" and vim.list_contains(cmd, "json"), "opencode: build_cmd shape")
check(vim.list_contains(cmd, "--dir") and vim.list_contains(cmd, "/wt/path"), "opencode: --dir pins the worktree")
check(
  vim.list_contains(cmd, "--auto") and vim.list_contains(cmd, "anthropic/claude-haiku-4-5") and cmd[#cmd] == "p",
  "opencode: yolo -> --auto, model, prompt last"
)
check(
  type(opencode.unsupported_modes) == "table" and type(opencode.unsupported_modes.acceptEdits) == "string",
  "opencode: declares acceptEdits unsupported"
)

-- ── partial result accumulation in the runner ────────────────────────
do
  local runner = require("hangar.runner")
  local run = { events = {} }
  runner._apply_event(run, { kind = "result", partial = true, cost = 0.01 })
  runner._apply_event(run, { kind = "result", partial = true, cost = 0.02 })
  check(#run.events == 0, "runner: partial results add no transcript entries")
  check(math.abs(run.cost - 0.03) < 1e-9 and run.turns == 2, "runner: partial results accumulate cost + turns")
end

-- ── delta coalescing in the runner ───────────────────────────────────
do
  local runner = require("hangar.runner")
  local run = { events = {} }
  runner._apply_event(run, { kind = "text", text = "hel", delta = true })
  runner._apply_event(run, { kind = "text", text = "lo", delta = true })
  runner._apply_event(run, { kind = "tool_use", tool = "x", summary = "" })
  runner._apply_event(run, { kind = "text", text = "bye", delta = true })
  check(#run.events == 3, "runner: text deltas coalesce")
  check(run.events[1].text == "hello", "runner: coalesced text content")
  check(run.events[3].text == "bye", "runner: coalescing stops at non-text events")
end

-- ── completion notifications ─────────────────────────────────────────
do
  local runner = require("hangar.runner")
  local hangar = require("hangar")
  local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-notify-XXXXXX")
  sh(repo, { "git", "init", "-b", "main" })
  sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
  sh(repo, { "git", "config", "user.name", "hangar-test" })
  sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })

  local next_id = 0
  local function mkrun()
    next_id = next_id + 1
    local id = "n" .. next_id
    local run = { id = id, status = "running", started = os.time() - 65, events = {}, worktree = repo, prompt = "p" }
    runner.runs[id] = run
    return run
  end

  local got
  hangar.setup({
    notify = function(r)
      got = r
    end,
  })
  local run = mkrun()
  runner._finish(run, 0)
  check(got == run and run.status == "done", "notify: function sink receives the run")

  hangar.setup({ notify = false })
  local called = false
  local orig_notify = vim.notify
  vim.notify = function()
    called = true
  end
  run = mkrun()
  runner._finish(run, 1)
  vim.notify = orig_notify
  check(not called and run.status == "failed", "notify: false is silent")

  hangar.setup({ notify = true })
  local msg, lvl
  vim.notify = function(m, l)
    msg, lvl = m, l
  end
  run = mkrun()
  run.cost = 0.05
  runner._finish(run, 0)
  vim.notify = orig_notify
  check(
    msg and msg:find(run.id, 1, true) and msg:find("done", 1, true) and msg:find("$0.05", 1, true) ~= nil,
    "notify: message carries id, status, elapsed, cost"
  )
  check(lvl == vim.log.levels.INFO, "notify: done notifies at INFO")

  vim.notify = function(m, l)
    msg, lvl = m, l
  end
  run = mkrun()
  run.error = "exploded"
  runner._finish(run, 1)
  vim.notify = orig_notify
  check(msg and msg:find("exploded", 1, true) and lvl == vim.log.levels.ERROR, "notify: failure carries the error")

  -- suppressed while the dashboard already shows the change live
  local prev = vim.uv.cwd()
  vim.fn.chdir(repo)
  require("hangar.ui.dashboard").open()
  check(require("hangar.ui.dashboard").is_open(), "notify: dashboard opens headless")
  vim.notify = function()
    called = true
  end
  called = false
  run = mkrun()
  runner._finish(run, 0)
  vim.notify = orig_notify
  check(not called, "notify: suppressed while dashboard is open")
  require("hangar.ui.dashboard").close()
  vim.fn.chdir(prev)

  for id in pairs(runner.runs) do
    if id:match("^n%d+$") then
      runner.runs[id] = nil
    end
  end
end

-- ── concurrency cap + spawn queue ────────────────────────────────────
do
  -- fake adapter: a real (cheap) process the runner can spawn and kill
  package.preload["hangar.adapters.fake"] = function()
    return {
      name = "fake",
      build_cmd = function()
        return { "sleep", "30" }
      end,
      parse_line = function()
        return nil
      end,
    }
  end
  local runner = require("hangar.runner")
  local hangar = require("hangar")
  local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-queue-XXXXXX")
  sh(repo, { "git", "init", "-b", "main" })
  sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
  sh(repo, { "git", "config", "user.name", "hangar-test" })
  sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
  local prev = vim.uv.cwd()
  vim.fn.chdir(repo)

  hangar.setup({ max_concurrent = 1, notify = false })
  local opts = { permission_mode = "bypassPermissions", adapter = "fake" }
  local r1 = assert(runner.spawn("first", vim.deepcopy(opts)))
  local r2 = assert(runner.spawn("second", vim.deepcopy(opts)))
  local r3 = assert(runner.spawn("third", vim.deepcopy(opts)))
  check(r1.status == "running" and r1.worktree ~= nil and r1.pid ~= nil, "queue: first run starts under the cap")
  check(r2.status == "queued" and r2.worktree == nil and r2.pid == nil, "queue: overflow spawn parks as queued")
  check(r3.status == "queued", "queue: further spawns keep queueing")
  check(require("hangar.status").text():find("◌", 1, true) ~= nil, "queue: statusline shows queued count")

  local ok = runner.kill(r3.id)
  check(ok and r3.status == "killed", "queue: queued run can be killed without a job")
  local dok = runner.discard(r3.id)
  check(dok and runner.get(r3.id) == nil, "queue: killed queued run can be discarded")

  local mok, merr = runner.merge(r2.id)
  check(mok == false and merr:find("not started", 1, true) ~= nil, "queue: merge rejects a queued run")

  runner.kill(r1.id)
  local promoted = vim.wait(10000, function()
    return r2.status == "running"
  end, 50)
  check(promoted and r2.worktree ~= nil and r2.pid ~= nil, "queue: freeing a slot promotes the oldest queued run")
  check(r1.status == "killed", "queue: killed run stays killed")

  runner.kill(r2.id)
  vim.wait(10000, function()
    return r2.exit_code ~= nil
  end, 50)
  runner.discard(r1.id)
  runner.discard(r2.id)
  hangar.config.max_concurrent = nil
  vim.fn.chdir(prev)
end

-- ── detached runs + resume preconditions ─────────────────────────────
do
  local runner = require("hangar.runner")
  local root = "/detach/test"

  local proc = vim.system({ "sleep", "30" })
  check(runner._classify_loaded({ pid = proc.pid }) == "detached", "detached: live pid classifies as detached")
  proc:kill(9)
  proc:wait()
  check(runner._classify_loaded({ pid = proc.pid }) == "orphaned", "detached: dead pid classifies as orphaned")
  check(runner._classify_loaded({}) == "orphaned", "detached: missing pid classifies as orphaned")

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
  check(mok == false and merr:find("running", 1, true) ~= nil, "detached: merge blocked while alive")
  local dok, derr = runner.discard("d2")
  check(dok == false and derr:find("kill", 1, true) ~= nil, "detached: discard blocked while alive")
  check(runner.kill("d2") == true and run.status == "killed", "detached: kill signals the pid directly")
  proc3:wait()

  local rok, rerr = runner.resume("d2")
  check(rok == false and rerr:find("killed", 1, true) ~= nil, "resume: only orphaned runs resume")
  run = { id = "d3", root = root, status = "orphaned", adapter = "claude_code", started = 3, events = {}, prompt = "p" }
  runner.runs.d3 = run
  rok, rerr = runner.resume("d3")
  check(rok == false and rerr:find("session id", 1, true) ~= nil, "resume: needs a captured session id")
  run.session_id = "sess"
  run.worktree = "/no/such/dir"
  rok, rerr = runner.resume("d3")
  check(rok == false and rerr:find("worktree", 1, true) ~= nil, "resume: needs the worktree on disk")
  run = { id = "d4", root = root, status = "orphaned", adapter = "fake", started = 4, events = {}, prompt = "p" }
  runner.runs.d4 = run
  rok, rerr = runner.resume("d4")
  check(rok == false and rerr:find("does not support", 1, true) ~= nil, "resume: adapter without resume errors")

  for _, id in ipairs({ "d1", "d2", "d3", "d4" }) do
    runner.runs[id] = nil
  end
end

-- ── iterate with feedback ────────────────────────────────────────────
do
  local runner = require("hangar.runner")
  check(
    runner._iterate_prompt({ prompt = "do x" }, "missed y") == "do x\n\nPrevious attempt feedback: missed y",
    "iterate: fresh prompt folds in feedback"
  )

  local tmp = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-iter-XXXXXX")
  local plain = { build_cmd = function() end, parse_line = function() end }
  local resumable = vim.tbl_extend("force", plain, { build_resume_cmd = function() end })
  check(
    runner._iterate_mode({ session_id = "s", worktree = tmp }, resumable) == "resume",
    "iterate: resume with session + worktree + adapter support"
  )
  check(runner._iterate_mode({ session_id = "s", worktree = tmp }, plain) == "fresh", "iterate: fresh without resume")
  check(runner._iterate_mode({ worktree = tmp }, resumable) == "fresh", "iterate: fresh without a session id")
  check(
    runner._iterate_mode({ session_id = "s", worktree = tmp .. "/gone" }, resumable) == "fresh",
    "iterate: fresh when the worktree is gone"
  )

  local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-iterrepo-XXXXXX")
  sh(repo, { "git", "init", "-b", "main" })
  sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
  sh(repo, { "git", "config", "user.name", "hangar-test" })
  sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
  local prev = vim.uv.cwd()
  vim.fn.chdir(repo)
  local opts = { permission_mode = "bypassPermissions", adapter = "fake" }

  -- fresh path: no resumable session -> new worktree, feedback in the prompt
  local r1 = assert(runner.spawn("build a thing", vim.deepcopy(opts)))
  runner.kill(r1.id)
  vim.wait(10000, function()
    return r1.exit_code ~= nil
  end, 50)
  local r2, ierr = runner.iterate(r1.id, "make it better")
  check(r2 ~= nil, "iterate: fresh iteration spawns a run" .. (ierr and (" (" .. ierr .. ")") or ""))
  assert(r2)
  check(r1.group ~= nil and r2.group == r1.group, "iterate: runs share a lineage group")
  check(r1.attempt == 1 and r2.attempt == 2, "iterate: attempt numbering")
  check(r2.prompt:find("Previous attempt feedback", 1, true) ~= nil, "iterate: fresh prompt carries feedback")
  check(r1.worktree ~= nil and r2.worktree ~= r1.worktree, "iterate: fresh path keeps worktrees separate")

  -- resume path: the follow-up run takes over worktree + branch + session
  package.preload["hangar.adapters.fakeresume"] = function()
    return {
      name = "fakeresume",
      build_cmd = function()
        return { "sleep", "30" }
      end,
      build_resume_cmd = function()
        return { "sleep", "30" }
      end,
      parse_line = function()
        return nil
      end,
    }
  end
  local r3 = assert(runner.spawn("task", { permission_mode = "bypassPermissions", adapter = "fakeresume" }))
  runner.kill(r3.id)
  vim.wait(10000, function()
    return r3.exit_code ~= nil
  end, 50)
  r3.session_id = "sess-3" -- the fake adapter emits no init event
  local wt3, br3 = r3.worktree, r3.branch
  local r4 = assert(runner.iterate(r3.id, "again"))
  check(r4.worktree == wt3 and r4.branch == br3, "iterate: resume run takes over worktree + branch")
  check(r3.worktree == nil and r3.branch == nil, "iterate: superseded run releases worktree + branch")
  check(r4.status == "running" and r4.session_id == "sess-3", "iterate: resume run is live with the session")
  check(r4.prompt == "again", "iterate: resume prompt is just the feedback")

  for _, r in ipairs({ r2, r4 }) do
    runner.kill(r.id)
    vim.wait(10000, function()
      return r.exit_code ~= nil
    end, 50)
  end
  for _, r in ipairs({ r1, r2, r3, r4 }) do
    runner.discard(r.id)
  end
  vim.fn.chdir(prev)
end

-- ── merge conflicts: detect, rebase, retry ───────────────────────────
do
  local worktree = require("hangar.worktree")
  local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
  end
  local function mkrepo()
    local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-conflict-XXXXXX")
    sh(repo, { "git", "init", "-b", "main" })
    sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
    sh(repo, { "git", "config", "user.name", "hangar-test" })
    write(repo .. "/README.md", "base\n")
    sh(repo, { "git", "add", "-A" })
    sh(repo, { "git", "commit", "-m", "init" })
    return repo
  end
  local function commit_all(dir, msg)
    sh(dir, { "git", "add", "-A" })
    sh(dir, { "git", "commit", "-m", msg, "--no-verify" })
  end

  -- both sides edit the same line: merge fails rebaseable, root stays pristine
  local repo = mkrepo()
  local wt = worktree.create(repo, "c1")
  local run = { root = repo, worktree = wt.path, branch = wt.branch, base = wt.base, prompt = "p" }
  write(wt.path .. "/README.md", "agent line\n")
  commit_all(wt.path, "agent edit")
  write(repo .. "/README.md", "user line\n")
  commit_all(repo, "user edit")
  local ok, _, meta = worktree.merge(run, "squash")
  check(ok == false and meta ~= nil and meta.rebaseable == true, "conflict: content conflict is rebaseable")
  check(sh(repo, { "git", "status", "--porcelain" }) == "", "conflict: root pristine after aborted merge")
  local sha_before = sh(wt.path, { "git", "rev-parse", "HEAD" })
  local rok, rerr = worktree.rebase_onto_head(run)
  check(rok == false and rerr:find("conflict", 1, true) ~= nil, "conflict: rebase aborts on real conflicts")
  check(sh(wt.path, { "git", "rev-parse", "HEAD" }) == sha_before, "conflict: branch untouched by aborted rebase")

  -- non-overlapping divergence with ff: rebase then retry succeeds
  local repo2 = mkrepo()
  local wt2 = worktree.create(repo2, "c2")
  local run2 = { root = repo2, worktree = wt2.path, branch = wt2.branch, base = wt2.base, prompt = "p" }
  write(wt2.path .. "/agent.txt", "agent\n")
  commit_all(wt2.path, "agent file")
  write(repo2 .. "/user.txt", "user\n")
  commit_all(repo2, "user file")
  ok, _, meta = worktree.merge(run2, "ff")
  check(ok == false and meta ~= nil and meta.rebaseable == true, "conflict: ff divergence is rebaseable")
  check(worktree.rebase_onto_head(run2) == true, "conflict: rebase onto HEAD succeeds")
  check(run2.base == sh(repo2, { "git", "rev-parse", "HEAD" }), "conflict: run.base moves to the new HEAD")
  check(worktree.merge(run2, "ff") == true, "conflict: retried ff merge succeeds")
  check(
    vim.uv.fs_stat(repo2 .. "/agent.txt") ~= nil and vim.uv.fs_stat(repo2 .. "/user.txt") ~= nil,
    "conflict: both sides' changes land"
  )

  -- the full runner path the dashboard uses (rebase_and_merge on a run record)
  local runner = require("hangar.runner")
  local repo3 = mkrepo()
  local wt3 = worktree.create(repo3, "c3")
  local run3 = {
    id = "c3",
    root = repo3,
    worktree = wt3.path,
    branch = wt3.branch,
    base = wt3.base,
    prompt = "p",
    status = "done",
    started = 1,
    events = {},
  }
  runner.runs.c3 = run3
  write(wt3.path .. "/agent.txt", "agent\n")
  commit_all(wt3.path, "agent file")
  write(repo3 .. "/user.txt", "user\n")
  commit_all(repo3, "user file")
  local mok, _, mmeta = runner.merge("c3", "ff")
  check(mok == false and mmeta and mmeta.rebaseable, "conflict: runner.merge surfaces rebaseable meta")
  check(runner.rebase_and_merge("c3", "ff") == true, "conflict: rebase_and_merge lands the run")
  check(run3.status == "merged", "conflict: run marked merged after rebase-and-retry")
  runner.runs.c3 = nil
end

-- ── adapter registry ─────────────────────────────────────────────────
local registry = require("hangar.adapters")
check(registry.get("claude_code") ~= nil, "registry: resolves claude_code")
check(registry.get("codex") ~= nil, "registry: resolves codex")
check(registry.get("no_such_adapter") == nil, "registry: unknown adapter -> nil")
check(select(2, registry.get("no_such_adapter")):find("available", 1, true) ~= nil, "registry: error lists available")
check(
  vim.list_contains(registry.available(), "codex") and not vim.list_contains(registry.available(), "util"),
  "registry: available() lists adapters only"
)

-- ── unsupported permission modes fail fast at spawn ──────────────────
do
  local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-safe-XXXXXX")
  sh(repo, { "git", "init", "-b", "main" })
  local prev = vim.uv.cwd()
  vim.fn.chdir(repo)
  local runner = require("hangar.runner")
  local run, serr = runner.spawn("p", { permission_mode = "acceptEdits", adapter = "opencode" })
  check(run == nil and serr and serr:find("yolo", 1, true) ~= nil, "spawn: opencode --safe fails fast")
  local wt_list = sh(repo, { "git", "worktree", "list" })
  check(select(2, wt_list:gsub("\n", "")) == 0, "spawn: fail-fast leaves no worktree behind")
  vim.fn.chdir(prev)
end

-- ── spawn arg parsing ────────────────────────────────────────────────
local hangar = require("hangar")
hangar.setup({})

local parsed = hangar._parse_spawn_args({ "--yolo", "--adapter", "codex", "fix", "the", "bug" })
check(parsed and parsed.adapter == "codex" and parsed.prompt == "fix the bug", "args: --adapter parsed")
parsed = hangar._parse_spawn_args({ "--yolo", "do it" })
check(parsed and parsed.adapter == nil, "args: adapter defaults to nil (config decides)")
local _, perr = hangar._parse_spawn_args({ "--yolo", "--adapter" })
check(perr and perr:find("--adapter", 1, true), "args: --adapter without value errors")

parsed = hangar._parse_spawn_args({ "--yolo", "--n", "3", "fix", "it" })
check(parsed and parsed.n == 3 and parsed.prompt == "fix it", "args: --n parsed")
parsed = hangar._parse_spawn_args({ "--yolo", "plain prompt" })
check(parsed and parsed.n == nil, "args: n defaults to nil (single run)")
_, perr = hangar._parse_spawn_args({ "--yolo", "--n", "three", "x" })
check(perr and perr:find("whole number", 1, true), "args: --n rejects non-numbers")
_, perr = hangar._parse_spawn_args({ "--yolo", "--n", "0", "x" })
check(perr, "args: --n rejects 0")
_, perr = hangar._parse_spawn_args({ "--yolo", "--n", "99", "x" })
check(perr, "args: --n rejects out-of-range counts")

-- ── statusline component ─────────────────────────────────────────────
do
  local repo = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-status-XXXXXX")
  sh(repo, { "git", "init", "-b", "main" })
  local prev = vim.uv.cwd()
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

-- ── integration tests (real agent runs) ──────────────────────────────
---Fast/cheap model per adapter for e2e runs; nil = the CLI's default.
local E2E_MODEL = { claude_code = "haiku" }

---@param spec string adapter name, optionally with a ":safe" suffix to run acceptEdits
local function run_e2e(spec)
  local adapter_name, mode = spec:match("^([^:]+):?(.*)$")
  local permission = mode == "safe" and "acceptEdits" or "bypassPermissions"
  io.write(("\n-- integration: real %s run (this takes a minute) --\n"):format(spec))
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

local integration_at
for i, a in ipairs(arg) do
  if a == "--integration" then
    integration_at = i
    break
  end
end
if integration_at then
  local names = vim.list_slice(arg, integration_at + 1)
  if #names == 0 then
    names = { "claude_code" }
  end
  for _, name in ipairs(names) do
    run_e2e(name)
  end
end

io.write(failed == 0 and "\nALL PASS\n" or ("\n" .. failed .. " FAILURES\n"))
os.exit(failed == 0 and 0 or 1)
