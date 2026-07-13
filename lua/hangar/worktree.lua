---Git worktree lifecycle + merge helpers. All git calls are synchronous
---`vim.system(...):wait()` with an explicit cwd; these commands are fast.
---
---Worktrees live under stdpath("cache"), OUTSIDE the repo: agent CLIs
---(claude, opencode) resolve their workspace upward from cwd, and a
---worktree nested inside the repo lets an agent using workspace-rooted
---absolute paths write straight into the user's main tree.
local M = {}

---Run a git command, return { code, stdout, stderr }.
---@param cwd string
---@param args string[]
local function git(cwd, args)
  local cmd = vim.list_extend({ "git" }, args)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  return {
    code = res.code,
    stdout = vim.trim(res.stdout or ""),
    stderr = vim.trim(res.stderr or ""),
  }
end

---@param cwd string
---@param args string[]
---@return string stdout
local function git_or_err(cwd, args)
  local res = git(cwd, args)
  if res.code ~= 0 then
    error(("git %s failed: %s"):format(table.concat(args, " "), res.stderr), 0)
  end
  return res.stdout
end

---Repo root of `dir` (or cwd), or nil + error message.
---@return string|nil root
---@return string|nil err
function M.root(dir)
  local res = git(dir or vim.uv.cwd(), { "rev-parse", "--show-toplevel" })
  if res.code ~= 0 then
    return nil, "not a git repository"
  end
  return res.stdout
end

---Directory that holds this repo's worktrees, unique per repo root.
---@param root string
---@return string
function M.home(root)
  local key = vim.fn.fnamemodify(root, ":t") .. "-" .. vim.fn.sha256(root):sub(1, 8)
  return vim.fn.stdpath("cache") .. "/hangar/worktrees/" .. key
end

---Create a worktree + branch for a run. Returns { path, branch, base }.
---@param root string
---@param run_id string
function M.create(root, run_id)
  local head = git(root, { "rev-parse", "HEAD" })
  if head.code ~= 0 then
    error("repository has no commits yet; hangar needs a base commit to branch from", 0)
  end
  local path = M.home(root) .. "/" .. run_id
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local branch = "hangar/" .. run_id
  git_or_err(root, { "worktree", "add", path, "-b", branch })
  return { path = path, branch = branch, base = head.stdout }
end

---Remove a run's worktree and branch (best-effort, forced). Queued runs
---have neither yet.
---@param run { root: string, worktree: string|nil, branch: string|nil }
function M.remove(run)
  if run.worktree then
    git(run.root, { "worktree", "remove", "--force", run.worktree })
  end
  if run.branch then
    git(run.root, { "branch", "-D", run.branch })
  end
  git(run.root, { "worktree", "prune" })
end

---True if the run's worktree has uncommitted or untracked changes.
function M.is_dirty(run)
  local res = git(run.worktree, { "status", "--porcelain" })
  return res.code == 0 and res.stdout ~= ""
end

---Commit everything in the run's worktree.
---@param run table
---@param msg string
function M.commit_all(run, msg)
  git_or_err(run.worktree, { "add", "-A" })
  git_or_err(run.worktree, { "commit", "-m", msg, "--no-verify" })
end

---Changed files of a run vs its base: list of { status = "M"|"A"|"D"|..., path = string }.
---Includes uncommitted tracked changes and untracked files while a run is live.
---@param run table
---@return table[]
function M.changed_files(run)
  local files, seen = {}, {}
  local function add(status, path)
    if path ~= "" and not seen[path] then
      seen[path] = true
      files[#files + 1] = { status = status, path = path }
    end
  end
  if not run.worktree then
    return files -- queued run: nothing on disk yet
  end
  if vim.uv.fs_stat(run.worktree) then
    local res = git(run.worktree, { "diff", "--name-status", run.base })
    for line in vim.gsplit(res.stdout, "\n", { plain = true }) do
      local status, path = line:match("^(%S+)%s+(.+)$")
      if status then
        add(status:sub(1, 1), path)
      end
    end
    local untracked = git(run.worktree, { "ls-files", "--others", "--exclude-standard" })
    for line in vim.gsplit(untracked.stdout, "\n", { plain = true }) do
      add("A", line)
    end
  else
    -- worktree gone (e.g. orphaned after restart + clean); fall back to branch diff
    local res = git(run.root, { "diff", "--name-status", run.base .. "..." .. run.branch })
    for line in vim.gsplit(res.stdout, "\n", { plain = true }) do
      local status, path = line:match("^(%S+)%s+(.+)$")
      if status then
        add(status:sub(1, 1), path)
      end
    end
  end
  return files
end

---Contents of `path` at the run's base commit (for diffsplit). nil if absent at base.
function M.show_base(run, path)
  local res = git(run.root, { "show", run.base .. ":" .. path })
  if res.code ~= 0 then
    return nil
  end
  return res.stdout
end

---Merge a run's branch into the user's current branch at root.
---@param run table
---@param strategy "squash"|"ff"|"merge"
---@return boolean ok
---@return string|nil err
---@return { rebaseable: boolean }|nil meta on failure: whether rebasing the
---run branch onto HEAD (see |M.rebase_onto_head|) could make the merge work
function M.merge(run, strategy)
  local dirty = git(run.root, { "status", "--porcelain" })
  if dirty.stdout ~= "" then
    return false, "your working tree is dirty; commit or stash before merging"
  end
  if strategy == "squash" then
    local res = git(run.root, { "merge", "--squash", run.branch })
    if res.code ~= 0 then
      -- probe for real content conflicts before the cleanup wipes the index
      local conflicted = git(run.root, { "ls-files", "-u" }).stdout ~= ""
      git(run.root, { "merge", "--abort" })
      git(run.root, { "reset", "--merge" })
      return false, "squash merge failed: " .. res.stderr, { rebaseable = conflicted }
    end
    local msg = ("hangar: %s"):format((run.prompt or run.branch):sub(1, 72))
    local commit = git(run.root, { "commit", "-m", msg, "--no-verify" })
    if commit.code ~= 0 then
      git(run.root, { "reset", "--merge" })
      return false, "commit after squash failed: " .. commit.stderr
    end
  else
    local flag = strategy == "ff" and "--ff-only" or "--no-ff"
    local res = git(run.root, { "merge", flag, run.branch })
    if res.code ~= 0 then
      local conflicted = git(run.root, { "ls-files", "-u" }).stdout ~= ""
      local diverged = strategy == "ff" and res.stderr:lower():find("fast%-forward") ~= nil
      git(run.root, { "merge", "--abort" })
      return false, "merge failed: " .. res.stderr, { rebaseable = conflicted or diverged }
    end
  end
  return true
end

---Rebase a run's branch onto the current HEAD of the main tree, inside the
---run's worktree. The agent branch is disposable, so rewriting it is fine.
---On conflict the rebase is aborted and the branch left untouched; on
---success run.base moves to the new HEAD so review diffs stay correct.
---@param run table
---@return boolean ok
---@return string|nil err
function M.rebase_onto_head(run)
  if not (run.worktree and vim.uv.fs_stat(run.worktree)) then
    return false, "run has no worktree to rebase in"
  end
  local head = git(run.root, { "rev-parse", "HEAD" })
  if head.code ~= 0 then
    return false, "cannot resolve HEAD: " .. head.stderr
  end
  local res = git(run.worktree, { "rebase", head.stdout })
  if res.code ~= 0 then
    git(run.worktree, { "rebase", "--abort" })
    return false, "rebase hit conflicts: " .. (res.stderr ~= "" and res.stderr or res.stdout)
  end
  run.base = head.stdout
  return true
end

return M
