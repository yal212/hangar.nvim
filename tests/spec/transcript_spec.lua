---Transcript renderer: one event stream in, pretty-printed lines + highlights out.
---@param harness table
return function(harness)
  local check = harness.check
  local runner = require("hangar.runner")
  local transcript = require("hangar.ui.transcript")

  -- One event per branch of event_lines(), including a kind it does not know.
  runner.runs["t1"] = {
    id = "t1",
    root = "/some/repo",
    status = "running",
    started = 1,
    prompt = "fix the flaky auth test",
    events = {
      { kind = "text", text = "first line\nsecond line" },
      { kind = "tool_use", tool = "Edit", summary = "src/auth.js" },
      { kind = "tool_use", tool = "Bash", summary = "" },
      { kind = "tool_result", text = "ok", is_error = false },
      { kind = "tool_result", text = "boom", is_error = true },
      { kind = "sausage", text = "not a real event kind" },
    },
  }

  transcript.open("t1")
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")

  check(
    vim.api.nvim_buf_get_name(buf):find("hangar://transcript/t1", 1, true) ~= nil,
    "transcript: buffer is named per run"
  )
  check(lines[1] == "prompt: fix the flaky auth test", "transcript: first line is the prompt")
  check(lines[2] == "", "transcript: prompt is followed by a blank line")
  check(lines[3] == "first line" and lines[4] == "second line", "transcript: multi-line text is split across lines")
  check(text:find("⚒ Edit src/auth.js", 1, true) ~= nil, "transcript: tool_use renders tool and summary")
  check(text:find("⚒ Bash\n", 1, true) ~= nil, "transcript: tool_use with an empty summary has no trailing space")
  check(text:find("  → ok", 1, true) ~= nil, "transcript: a tool_result is indented with an arrow")
  check(text:find("  ✗ boom", 1, true) ~= nil, "transcript: a failed tool_result is marked with a cross")
  check(text:find("not a real event kind", 1, true) == nil, "transcript: an unknown event kind renders nothing")
  check(lines[#lines] == "● running…", "transcript: a live run ends with the running marker")
  check(not vim.bo[buf].modifiable, "transcript: the buffer is read-only")

  -- highlights: the tool_use line is marked, the plain text line is not
  local ns = vim.api.nvim_create_namespace("hangar_transcript")
  local marked = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    marked[m[2]] = m[4].hl_group
  end
  ---0-indexed buffer line holding `needle`. Asserts rather than returning nil:
  ---a miss would make the `== nil` highlight checks below pass vacuously.
  local function line_of(needle)
    for i, l in ipairs(lines) do
      if l:find(needle, 1, true) then
        return i - 1 -- extmarks are 0-indexed
      end
    end
    error("transcript spec: no rendered line contains " .. needle, 0)
  end
  check(marked[0] == "HangarDim", "transcript: the prompt header is dimmed")
  check(marked[line_of("⚒ Edit")] == "HangarToolUse", "transcript: tool_use lines are highlighted")
  check(marked[line_of("✗ boom")] == "HangarFailed", "transcript: failed tool_results are highlighted as errors")
  check(marked[line_of("first line")] == nil, "transcript: plain text carries no highlight")

  -- #39's open_bufs cache: reopening must reuse the buffer, not stack splits
  local wins_before = #vim.api.nvim_list_wins()
  transcript.open("t1")
  check(vim.api.nvim_get_current_buf() == buf, "transcript: reopening a run reuses its buffer")
  check(#vim.api.nvim_list_wins() == wins_before, "transcript: reopening does not stack another split")

  -- a finished run: no running marker, and the result footer is formatted
  runner.runs["t2"] = {
    id = "t2",
    root = "/some/repo",
    status = "done",
    started = 2,
    prompt = "add dark mode",
    events = {
      { kind = "result", is_error = false, turns = 3, cost = 0.1234, duration_ms = 12000 },
    },
  }
  transcript.open("t2")
  local done_buf = vim.api.nvim_get_current_buf()
  local done = table.concat(vim.api.nvim_buf_get_lines(done_buf, 0, -1, false), "\n")
  check(done:find("● running…", 1, true) == nil, "transcript: a finished run has no running marker")
  check(
    done:find("✓ finished  ·  3 turns  ·  $0.1234  ·  12s", 1, true) ~= nil,
    "transcript: the result footer carries turns, 4-decimal cost and seconds"
  )

  -- an errored result flips the marker and the highlight
  runner.runs["t3"] = {
    id = "t3",
    root = "/some/repo",
    status = "failed",
    started = 3,
    prompt = "break everything",
    events = { { kind = "result", is_error = true } },
  }
  transcript.open("t3")
  local fail_buf = vim.api.nvim_get_current_buf()
  local failed = vim.api.nvim_buf_get_lines(fail_buf, 0, -1, false)
  check(failed[#failed] == "✗ finished with error", "transcript: an errored result says so, with no stats appended")

  -- An iterated run's prompt always contains newlines (runner._iterate_prompt
  -- appends "\n\nPrevious attempt feedback: ..."), and nvim_buf_set_lines
  -- rejects a line containing one — opening such a transcript used to raise
  -- "'replacement string' item contains newlines".
  runner.runs["t4"] = {
    id = "t4",
    root = "/some/repo",
    status = "done",
    started = 4,
    prompt = "add dark mode\n\nPrevious attempt feedback: use the theme tokens",
    events = {},
  }
  local iterated_ok = pcall(transcript.open, "t4")
  check(iterated_ok, "transcript: a multi-line prompt does not break the buffer")
  local iterated_buf = vim.api.nvim_get_current_buf()
  check(
    iterated_ok
      and vim.api.nvim_buf_get_lines(iterated_buf, 0, 1, false)[1]
        == "prompt: add dark mode Previous attempt feedback: use the theme tokens",
    "transcript: a multi-line prompt collapses into the one-line header"
  )

  -- unknown run id: notifies rather than raising
  local notified
  local real_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    notified = msg
  end
  local ok = pcall(transcript.open, "no-such-run")
  vim.notify = real_notify
  check(
    ok and notified and tostring(notified):find("no such run", 1, true) ~= nil,
    "transcript: unknown run id notifies"
  )

  -- the run is discarded (or cleaned) while its transcript is open
  runner.runs["t5"] = { id = "t5", root = "/some/repo", status = "done", started = 1, prompt = "p", events = {} }
  transcript.open("t5")
  local gone_buf = vim.api.nvim_get_current_buf()
  runner.runs["t5"] = nil
  -- an erroring autocmd callback is reported as a message, not raised
  vim.v.errmsg = ""
  vim.api.nvim_exec_autocmds("User", { pattern = "HangarRunUpdate", data = { id = "t5" } })
  check(vim.v.errmsg == "", "transcript: a discarded run does not error the update (" .. vim.v.errmsg .. ")")
  local gone_lines = vim.api.nvim_buf_get_lines(gone_buf, 0, -1, false)
  check(gone_lines[#gone_lines]:find("discarded", 1, true) ~= nil, "transcript: says the run was discarded")
  check(gone_lines[1] == "prompt: p", "transcript: the discarded run's transcript stays readable")
  local again_ok = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "HangarRunUpdate", data = { id = "t5" } })
  check(
    again_ok and #vim.api.nvim_buf_get_lines(gone_buf, 0, -1, false) == #gone_lines,
    "transcript: stops following once the run is gone"
  )

  for _, b in ipairs({ buf, done_buf, fail_buf, iterated_buf, gone_buf }) do
    for _, win in ipairs(vim.fn.win_findbuf(b)) do
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, id in ipairs({ "t1", "t2", "t3", "t4" }) do
    runner.runs[id] = nil
  end
end
