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

local init_src = read("lua/hangar/init.lua")

-- The option list is taken from SCHEMA, not from vim.tbl_keys(hangar.config):
-- default_permission, model and max_concurrent all default to nil, so they are
-- absent from the runtime table and every check below used to skip them.
local options = vim.tbl_keys(hangar._SCHEMA)
table.sort(options)

-- 2. every config key is documented in both the README and the vimdoc
for _, key in ipairs(options) do
  want(readme:find(key, 1, true) ~= nil, ("config key %q is not mentioned in README.md"):format(key))
  want(vimdoc:find(key, 1, true) ~= nil, ("config key %q is not mentioned in doc/hangar.txt"):format(key))
end

-- 2a. SCHEMA and the M.config literal describe the same options. Compared
-- against the source text rather than the table, for the same nil-default
-- reason: a key whose default is nil is invisible at runtime.
local config_block = init_src:match("\nM%.config = {\n(.-)\n}\n")
want(config_block ~= nil, "could not locate the M.config table literal in lua/hangar/init.lua")
local declared = {}
-- only the literal's own keys: two-space indent at the start of a line, which
-- skips both the `---` prose above each option and the example tables inside it
for line in vim.gsplit(config_block or "", "\n", { plain = true }) do
  local key = line:match("^  ([%w_]+) = ")
  if key then
    declared[key] = true
  end
end
for _, key in ipairs(options) do
  want(declared[key], ("option %q is in SCHEMA but not in M.config"):format(key))
end
for key in pairs(declared) do
  want(hangar._SCHEMA[key], ("option %q is in M.config but not in SCHEMA, so setup() rejects it"):format(key))
end

-- 2b. every option is declared as an @field on BOTH annotation classes.
-- lua-language-server attaches types to a class through @field only, so an
-- option added to M.config without one silently drops out of setup()
-- completion and type checking — which is how issue #20 happened.
---@param class string
---@return table<string, true>
local function fields_of(class)
  local literal = class:gsub("%%.", "%%%%.") -- the dot in "hangar.Config" is a pattern wildcard
  local block = init_src:match("---@class " .. literal .. "\n(.-)\n%s*\n")
  local names = {}
  for name in (block or ""):gmatch("---@field ([%w_]+)") do
    names[name] = true
  end
  return names
end
for _, class in ipairs({ "hangar.Config", "hangar.Opts" }) do
  local fields = fields_of(class)
  want(next(fields) ~= nil, ("could not parse any @field entries for %s in lua/hangar/init.lua"):format(class))
  for _, key in ipairs(options) do
    want(fields[key], ("config key %q has no `---@field` entry on %s"):format(key, class))
  end
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
for _, key in ipairs(options) do
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
