---codex adapter: canned lines from a real `codex exec --json` run.
---@param harness table
return function(harness)
  local check = harness.check
  local ev, cmd, rcmd
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
end
