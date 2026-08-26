---Docs drift guard: asserts that what the code exposes is what the docs claim.
---
---  nvim --headless -l scripts/check-docs.lua
---
---Deliberately checks only mechanical facts — config keys, adapter names,
---subcommands, version, help tags. Prose is not checked: it would fail on
---harmless rewording and train people to ignore this job.
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.rtp:prepend(root)

local problems = {}

---@param cond any
---@param msg string
local function want(cond, msg)
  if not cond then
    problems[#problems + 1] = msg
  end
end

---@param name string
---@return string
local function read(name)
  local f = assert(io.open(root .. "/" .. name, "r"), "cannot read " .. name)
  local content = f:read("*a")
  f:close()
  return content
end

local readme = read("README.md")
local vimdoc = read("doc/hangar.txt")
local changelog = read("CHANGELOG.md")

local hangar = require("hangar")

-- 1. version agrees with the newest dated CHANGELOG heading
local latest = changelog:match("\n## %[(%d+%.%d+%.%d+)%] %- %d")
want(latest ~= nil, "CHANGELOG.md has no dated `## [X.Y.Z] - DATE` heading")
if latest then
  want(
    latest == hangar.version,
    ("version drift: init.lua says %q, newest CHANGELOG release is %q"):format(hangar.version, latest)
  )
end

-- 2. every config key is documented in both the README and the vimdoc
for _, key in ipairs(vim.tbl_keys(hangar.config)) do
  want(readme:find(key, 1, true) ~= nil, ("config key %q is not mentioned in README.md"):format(key))
  want(vimdoc:find(key, 1, true) ~= nil, ("config key %q is not mentioned in doc/hangar.txt"):format(key))
end

-- 3. every shipped adapter is listed in both
for _, name in ipairs(require("hangar.adapters").available()) do
  want(readme:find(name, 1, true) ~= nil, ("adapter %q is not mentioned in README.md"):format(name))
  want(vimdoc:find(name, 1, true) ~= nil, ("adapter %q is not mentioned in doc/hangar.txt"):format(name))
end

-- 4. every :Hangar subcommand the completion offers is documented
for _, sub in ipairs(hangar._complete("", ":Hangar ")) do
  want(
    vimdoc:find(":Hangar " .. sub, 1, true) ~= nil,
    ("subcommand %q is not documented in doc/hangar.txt"):format(sub)
  )
end

-- 5. every |hangar-xxx| cross-reference resolves to a *hangar-xxx* tag
local defined = {}
for tag in vimdoc:gmatch("%*(hangar[%w%-%.]*)%*") do
  defined[tag] = true
end
local seen = {}
for ref in vimdoc:gmatch("|(hangar[%w%-%.]*)|") do
  if not seen[ref] then
    seen[ref] = true
    want(defined[ref], ("doc/hangar.txt references |%s| but never defines the tag"):format(ref))
  end
end

-- 6. the setup() schema and the real config table describe the same options
for _, key in ipairs(vim.tbl_keys(hangar.config)) do
  want(
    #hangar._validate({ [key] = hangar.config[key] }) == 0,
    ("config key %q is rejected by setup() validation"):format(key)
  )
end

if #problems > 0 then
  table.sort(problems)
  io.write(("docs check failed (%d problem%s):\n"):format(#problems, #problems == 1 and "" or "s"))
  for _, p in ipairs(problems) do
    io.write("  - " .. p .. "\n")
  end
  os.exit(1)
end

io.write("docs check passed\n")
os.exit(0)
