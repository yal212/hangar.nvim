---Headless test harness. No plenary/busted — plain asserts + vim.wait.
---
---  All offline specs (free, no network, no API calls):
---    nvim --headless -l tests/run_tests.lua
---  One spec, by filename substring:
---    nvim --headless -l tests/run_tests.lua --filter codex
---  Include real end-to-end runs (spawns actual agent CLIs, costs money):
---    XDG_DATA_HOME=$(mktemp -d) nvim --headless -l tests/run_tests.lua --integration [adapter ...]
---  Adapter names default to claude_code; e.g. `--integration codex opencode`.
---  Append ":safe" to an adapter name to run it with acceptEdits, e.g. `claude_code:safe`.
---
---Specs live in tests/spec/*_spec.lua and each returns `function(harness)`.

local script = arg[0]
local plugin_root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.rtp:prepend(plugin_root)

-- opt-in coverage (CI): HANGAR_COVERAGE=1 with luacov on package.path.
-- Must start before any hangar module is required, or nothing is instrumented —
-- which is why specs are loaded lazily below rather than required up front.
local coverage = vim.env.HANGAR_COVERAGE == "1" and pcall(require, "luacov")

local harness = dofile(plugin_root .. "/tests/harness.lua")

-- never touch the user's real run registry, even without XDG_DATA_HOME set
require("hangar.store").set_state_dir(assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-state-XXXXXX")))

---Value following `flag` in the argument list, or nil.
local function arg_after(flag)
  for i, a in ipairs(arg) do
    if a == flag then
      return arg[i + 1], i
    end
  end
end

local filter = arg_after("--filter")

local specs = vim.fn.glob(plugin_root .. "/tests/spec/*_spec.lua", false, true)
table.sort(specs) -- deterministic order

local ran = 0
for _, path in ipairs(specs) do
  local name = vim.fn.fnamemodify(path, ":t:r")
  if not filter or name:find(filter, 1, true) then
    ran = ran + 1
    harness.reset_config() -- specs mutate hangar.config; keep them order-independent
    local ok, err = pcall(dofile(path), harness)
    if not ok then
      harness.failed = harness.failed + 1
      io.write(("FAIL %s crashed: %s\n"):format(name, err))
    end
  end
end

if filter and ran == 0 then
  io.write(("no specs matched --filter %s\n"):format(filter))
  os.exit(1)
end

local _, integration_at = arg_after("--integration")
if integration_at then
  local names = vim.list_slice(arg, integration_at + 1)
  -- stop at the next flag so `--integration --filter x` does not treat "--filter" as an adapter
  for i, a in ipairs(names) do
    if a:sub(1, 2) == "--" then
      names = vim.list_slice(names, 1, i - 1)
      break
    end
  end
  if #names == 0 then
    names = { "claude_code" }
  end
  harness.reset_config()
  dofile(plugin_root .. "/tests/integration/adapters_e2e.lua")(harness, names)
end

io.write(harness.failed == 0 and "\nALL PASS\n" or ("\n" .. harness.failed .. " FAILURES\n"))

-- os.exit skips luacov's atexit hook, which would leave the stats file empty
if coverage then
  pcall(function()
    require("luacov.runner").shutdown()
  end)
end

os.exit(harness.failed == 0 and 0 or 1)
