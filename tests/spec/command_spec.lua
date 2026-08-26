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

  -- setup() validation: typos and wrong types are reported, not silently merged
  local problems = hangar._validate({ adaptor = "codex" })
  check(#problems == 1 and problems[1]:find("adaptor", 1, true) ~= nil, "setup: unknown key is reported by name")
  check(problems[1]:find("did you mean", 1, true) ~= nil, "setup: near-miss key suggests the real one")
  check(#hangar._validate({ merge = 42 }) == 1, "setup: wrong type is reported")
  check(hangar._validate({ merge = 42 })[1]:find("string", 1, true) ~= nil, "setup: type error names the expected type")
  check(#hangar._validate({ merge = "nope" }) == 1, "setup: value outside the allowed set is reported")
  check(#hangar._validate({ merge = "ff" }) == 0, "setup: a valid value passes")
  check(#hangar._validate({ notify = false }) == 0, "setup: notify accepts a boolean")
  check(#hangar._validate({ notify = function() end }) == 0, "setup: notify accepts a function")
  check(#hangar._validate({ notify = "yes" }) == 1, "setup: notify rejects a string")
  check(#hangar._validate({ max_concurrent = 2 }) == 0, "setup: max_concurrent accepts a number")
  check(#hangar._validate({ default_permission = "yolo" }) == 0, "setup: default_permission accepts yolo")
  check(#hangar._validate({ default_permission = "wild" }) == 1, "setup: default_permission rejects other values")
  check(#hangar._validate({}) == 0, "setup: empty options are valid")
  check(#hangar._validate({ adaptor = "x", merge = 1 }) == 2, "setup: every problem is reported, not just the first")

  -- every schema key must be a real config key, or validation would reject
  -- an option the plugin actually reads
  for _, key in ipairs(vim.tbl_keys(hangar.config)) do
    check(#hangar._validate({ [key] = hangar.config[key] }) == 0, "setup: schema covers config key " .. key)
  end

  -- the deprecated alias still works, but warns
  local orig = vim.notify
  local warned
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(m, l)
    if l == vim.log.levels.WARN then
      warned = m
    end
  end
  hangar.setup({ claude_cmd = "my-claude" })
  vim.notify = orig
  check(warned and warned:find("deprecated", 1, true) ~= nil, "setup: claude_cmd warns that it is deprecated")
  check(warned and warned:find("0.3.0", 1, true) ~= nil, "setup: deprecation names the removal version")
  check(hangar.config.claude_cmd == "my-claude", "setup: claude_cmd still takes effect")
end
