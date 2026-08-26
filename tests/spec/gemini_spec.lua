---gemini adapter: canned lines per the CLI's StreamJsonFormatter schema.
---@param harness table
return function(harness)
  local check = harness.check
  local ev, cmd
  local gemini = require("hangar.adapters.gemini")

  ev =
    gemini.parse_line('{"type":"init","timestamp":"2026-07-13T10:00:00Z","session_id":"s-1","model":"gemini-2.5-pro"}')
  check(ev and ev.kind == "init" and ev.model == "gemini-2.5-pro" and ev.session_id == "s-1", "gemini: init event")

  check(
    gemini.parse_line('{"type":"message","role":"user","content":"the prompt"}') == nil,
    "gemini: user echo skipped"
  )

  ev = gemini.parse_line('{"type":"message","role":"assistant","content":"hel","delta":true}')
  check(ev and ev.kind == "text" and ev.text == "hel" and ev.delta == true, "gemini: assistant delta -> text")

  ev = gemini.parse_line(
    '{"type":"tool_use","tool_name":"write_file","tool_id":"t1","parameters":{"file_path":"/a/b.md"}}'
  )
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
end
