---Minimal test harness: assertion counter, shell helper, per-spec isolation.
---Specs receive this table and call `t.check(cond, label)`.
local M = {}

M.failed = 0
M.passed = 0

---Record one assertion. Prints TAP-ish `ok`/`FAIL` lines, as the suite always has.
---@param cond any truthy to pass
---@param label string
function M.check(cond, label)
  if cond then
    M.passed = M.passed + 1
    io.write("ok   " .. label .. "\n")
  else
    M.failed = M.failed + 1
    io.write("FAIL " .. label .. "\n")
  end
end

---Run a command, asserting it succeeded. Returns trimmed stdout.
---@param cwd string
---@param cmd string[]
---@return string stdout
function M.sh(cwd, cmd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert(res.code == 0, ("command failed: %s\n%s"):format(table.concat(cmd, " "), res.stderr))
  return vim.trim(res.stdout or "")
end

---Create a throwaway git repo with one empty commit. Returns its path.
---@param label string used in the temp directory name
---@return string repo
function M.git_repo(label)
  local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-" .. label .. "-XXXXXX"))
  M.sh(repo, { "git", "init", "-b", "main" })
  M.sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
  M.sh(repo, { "git", "config", "user.name", "hangar-test" })
  return repo
end

-- Stub adapters, registered once for every spec. They spawn a real but cheap
-- process the runner can start, poll and kill. Registering these centrally is
-- what keeps specs order-independent: they used to be declared inside whichever
-- section happened to run first, so a filtered run could fail on a missing adapter.
package.preload["hangar.adapters.fake"] = function()
  return {
    name = "fake",
    build_cmd = function()
      return { "sleep", "30" }
    end,
    parse_line = function()
      return nil
    end,
  }
end

-- same, plus a resumable session — exercises the iterate/resume path
package.preload["hangar.adapters.fakeresume"] = function()
  return {
    name = "fakeresume",
    build_cmd = function()
      return { "sleep", "30" }
    end,
    build_resume_cmd = function()
      return { "sleep", "30" }
    end,
    parse_line = function()
      return nil
    end,
  }
end

-- an agent CLI that is not installed: vim.system cannot even start it
M.MISSING_EXE = "hangar-test-no-such-agent-cli"
package.preload["hangar.adapters.missing"] = function()
  return {
    name = "missing",
    build_cmd = function()
      return { M.MISSING_EXE }
    end,
    build_resume_cmd = function()
      return { M.MISSING_EXE }
    end,
    parse_line = function()
      return nil
    end,
  }
end

-- Pristine config, captured before any spec mutates it. Specs call
-- hangar.setup(), which merges rather than replaces, so without an explicit
-- reset the notify/max_concurrent settings of one spec leak into the next and
-- results depend on file order — which would make --filter untrustworthy.
local pristine

---Restore `hangar.config` to its startup state. Called between spec files.
function M.reset_config()
  local hangar = require("hangar")
  pristine = pristine or vim.deepcopy(hangar.config)
  hangar.config = vim.deepcopy(pristine)
end

return M
