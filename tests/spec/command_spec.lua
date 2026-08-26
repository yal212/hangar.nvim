---:Hangar spawn argument parsing.
---@param harness table
return function(harness)
  local check = harness.check
  local hangar = require("hangar")
  hangar.setup({})

  local parsed = hangar._parse_spawn_args({ "--yolo", "--adapter", "codex", "fix", "the", "bug" })
  check(parsed and parsed.adapter == "codex" and parsed.prompt == "fix the bug", "args: --adapter parsed")
  parsed = hangar._parse_spawn_args({ "--yolo", "do it" })
  check(parsed and parsed.adapter == nil, "args: adapter defaults to nil (config decides)")
  local _, perr = hangar._parse_spawn_args({ "--yolo", "--adapter" })
  check(perr and perr ~= nil and perr:find("--adapter", 1, true), "args: --adapter without value errors")

  parsed = hangar._parse_spawn_args({ "--yolo", "--n", "3", "fix", "it" })
  check(parsed and parsed.n == 3 and parsed.prompt == "fix it", "args: --n parsed")
  parsed = hangar._parse_spawn_args({ "--yolo", "plain prompt" })
  check(parsed and parsed.n == nil, "args: n defaults to nil (single run)")
  _, perr = hangar._parse_spawn_args({ "--yolo", "--n", "three", "x" })
  check(perr and perr ~= nil and perr:find("whole number", 1, true), "args: --n rejects non-numbers")
  _, perr = hangar._parse_spawn_args({ "--yolo", "--n", "0", "x" })
  check(perr, "args: --n rejects 0")
  _, perr = hangar._parse_spawn_args({ "--yolo", "--n", "99", "x" })
  check(perr, "args: --n rejects out-of-range counts")
end
