---runner: partial result accumulation and text-delta coalescing.
---@param harness table
return function(harness)
  local check = harness.check
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

  -- ── a final line without a trailing newline ──────────────────────────
  do
    local runner = require("hangar.runner")
    local hangar = require("hangar")
    -- prints a text line, then an unterminated error result: the result must be
    -- parsed, and before finish() reads it, or the run would end "done"
    package.preload["hangar.adapters.nonewline"] = function()
      return {
        name = "nonewline",
        build_cmd = function()
          return { "printf", "text hello\\nresult boom" }
        end,
        parse_line = function(line)
          local kind, rest = line:match("^(%S+) (.*)$")
          if kind == "text" then
            return { kind = "text", text = rest }
          elseif kind == "result" then
            return { kind = "result", is_error = true, text = rest }
          end
        end,
      }
    end
    local repo = harness.git_repo("eof")
    harness.sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
    local prev = assert(vim.uv.cwd())
    vim.fn.chdir(repo)
    hangar.setup({ notify = false })
    local run = assert(runner.spawn("p", { permission_mode = "acceptEdits", adapter = "nonewline" }))
    vim.wait(10000, function()
      return run.exit_code ~= nil
    end, 20)
    check(#run.events == 2, "runner: an unterminated final line is still parsed")
    check(run.status == "failed" and run.error == "boom", "runner: the final line is applied before finish()")
    runner.discard(run.id)
    package.loaded["hangar.adapters.nonewline"] = nil
    package.preload["hangar.adapters.nonewline"] = nil
    vim.fn.chdir(prev)
  end
end
