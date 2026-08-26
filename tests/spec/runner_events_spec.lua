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
end
