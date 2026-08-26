---opencode adapter: canned lines from a real `opencode run --format json` run.
---@param harness table
return function(harness)
  local check = harness.check
  local ev, cmd
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
end
