---Shared adapter parser helpers: truncate() and input_summary().
---@param harness table
return function(harness)
  local check = harness.check
  local util = require("hangar.adapters.util")

  -- decode_line: the guard every adapter's parse_line opens with
  check(util.decode_line('{"a":1}').a == 1, "decode_line: decodes a JSON object")
  check(util.decode_line("") == nil, "decode_line: blank line")
  check(util.decode_line("not json at all") == nil, "decode_line: invalid JSON")
  check(util.decode_line("[1,2,3]") ~= nil, "decode_line: JSON arrays decode as tables")
  check(util.decode_line("42") == nil, "decode_line: non-object scalar")
  check(util.decode_line('"a string"') == nil, "decode_line: bare JSON string")

  -- truncate: collapses whitespace, then caps length with an ellipsis
  check(util.truncate("hello", 20) == "hello", "truncate: short strings pass through")
  check(util.truncate("a\n b\t\tc", 20) == "a b c", "truncate: collapses all whitespace runs to one space")
  check(util.truncate(("x"):rep(10), 10) == ("x"):rep(10), "truncate: exactly at the cap is untouched")
  local over = util.truncate(("x"):rep(11), 10)
  check(#over == 10 and over:sub(-3) == "...", "truncate: over the cap is cut to the cap, ellipsis included")

  -- input_summary: first matching key wins, in SUMMARY_KEYS order
  check(util.input_summary({ file_path = "/a/b.lua" }) == "/a/b.lua", "input_summary: file_path")
  check(util.input_summary({ filePath = "/a/b.lua" }) == "/a/b.lua", "input_summary: camelCase filePath")
  check(util.input_summary({ command = "ls -la" }) == "ls -la", "input_summary: command")
  check(util.input_summary({ pattern = "TODO" }) == "TODO", "input_summary: pattern")
  check(util.input_summary({ url = "https://example.com" }) == "https://example.com", "input_summary: url")
  check(
    util.input_summary({ query = "q", file_path = "/a/b.lua" }) == "/a/b.lua",
    "input_summary: earlier key in SUMMARY_KEYS wins over a later one"
  )
  check(util.input_summary({ file_path = ("y"):rep(80) }):len() == 60, "input_summary: truncates to 60")

  -- non-matches degrade to an empty string rather than erroring
  check(util.input_summary(nil) == "", "input_summary: nil input")
  check(util.input_summary("a string") == "", "input_summary: non-table input")
  check(util.input_summary({}) == "", "input_summary: no recognised keys")
  check(util.input_summary({ file_path = "" }) == "", "input_summary: empty value is skipped")
  check(util.input_summary({ file_path = 42 }) == "", "input_summary: non-string value is skipped")
end
