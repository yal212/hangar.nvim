---Shared helpers in hangar.util.
---@param harness table
return function(harness)
  local check = harness.check
  local util = require("hangar.util")

  -- utf8_prefix: a byte budget that never splits a character
  local cut = util.utf8_prefix
  check(cut("hello", 3) == "hel", "utf8_prefix: ASCII is cut at the byte budget")
  check(cut("hi", 10) == "hi", "utf8_prefix: a string within budget is returned whole")
  check(cut("hello", 0) == "", "utf8_prefix: a zero budget yields an empty string")
  check(cut(("é"):rep(5), 5) == "éé", "utf8_prefix: 2-byte characters are not split")
  check(cut(("修"):rep(3), 8) == "修修", "utf8_prefix: 3-byte characters are not split")
  check(cut(("修"):rep(3), 6) == "修修", "utf8_prefix: a budget on a boundary keeps the whole character")
  check(cut("😀😀", 7) == "😀", "utf8_prefix: 4-byte characters are not split")
  check(cut("a" .. ("修"):rep(20), 42) == "a" .. ("修"):rep(13), "utf8_prefix: mixed ASCII and CJK")
end
