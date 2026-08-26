---claude_code adapter: stream-json parsing and command building.
---@param harness table
return function(harness)
  local check = harness.check
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
end
