-- Static analysis config. Run: luacheck lua plugin tests
std = "luajit"

-- Neovim's runtime globals. `vim` is written to in tests (stubs), so it is
-- a writable global rather than read-only.
globals = { "vim" }

max_line_length = 120 -- matches stylua.toml and .editorconfig

files["tests/run_tests.lua"] = {
  -- canned CLI output is pasted verbatim as single-line JSON fixtures;
  -- wrapping them would stop them matching what the CLIs actually emit
  max_line_length = false,
}
