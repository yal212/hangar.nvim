---Persistence for the run registry: a JSON file under stdpath("data"), plus the
---liveness classification applied to runs a previous nvim session left behind.
---
---Split out of runner.lua so the run lifecycle does not also own file I/O.
---Tests point `set_state_dir` at a scratch directory so they never touch the
---user's real registry.
local M = {}

local state_dir_override

---Redirect persistence at `dir` instead of stdpath("data"). Used by the tests.
---@param dir string
function M.set_state_dir(dir)
  state_dir_override = dir
end

---Absolute path of the registry file.
---@return string
function M.path()
  return (state_dir_override or vim.fn.stdpath("data")) .. "/hangar/runs.json"
end

---True if the pid exists (signal 0 probes without killing).
---@param pid integer|nil
---@return boolean
function M.pid_alive(pid)
  return pid ~= nil and vim.uv.kill(pid, 0) == 0
end

---Status for a run persisted as "running" by a previous session: "detached"
---when its process is still alive, "orphaned" when it is gone.
---@param run { pid: integer|nil } any run-shaped table; only `pid` is read
---@return "detached"|"orphaned"
function M.classify_loaded(run)
  return M.pid_alive(run.pid) and "detached" or "orphaned"
end

---Write the registry. Failures are silent by design: losing run history is not
---worth interrupting the user mid-edit, and the runs themselves are unaffected.
---@param runs table<string, hangar.Run>
function M.save(runs)
  local path = M.path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.json.encode, runs)
  if ok then
    local f = io.open(path, "w")
    if f then
      f:write(encoded)
      f:close()
    end
  end
end

---Read and decode the registry. nil when absent, unreadable or corrupt — all
---of which are treated as "no history", never as an error.
---@return table<string, hangar.Run>|nil
function M.read()
  local f = io.open(M.path(), "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

---Persisted runs with their statuses reconciled against reality. Runs that were
---live in a previous session can't be reattached: if the process still exists
---they become "detached" (watch it finish, then resume), otherwise "orphaned"
---(the worktree is still reviewable/mergeable, and the session may be resumable).
---Queued runs are never auto-started on load — the prompt stays visible instead.
---@return table<string, hangar.Run>
function M.load()
  local runs = {}
  for id, run in pairs(M.read() or {}) do
    if run.status == "running" then
      run.status = M.classify_loaded(run)
    elseif run.status == "queued" then
      run.status = "killed"
      run.error = "queued run never started (nvim exited)"
    end
    runs[id] = run
  end
  return runs
end

return M
