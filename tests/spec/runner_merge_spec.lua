---runner: merge conflict detection, rebase, and retry.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  do
    local worktree = require("hangar.worktree")
    local function write(path, text)
      local f = assert(io.open(path, "w"))
      f:write(text)
      f:close()
    end
    local function mkrepo()
      local repo = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-conflict-XXXXXX"))
      sh(repo, { "git", "init", "-b", "main" })
      sh(repo, { "git", "config", "user.email", "test@hangar.nvim" })
      sh(repo, { "git", "config", "user.name", "hangar-test" })
      write(repo .. "/README.md", "base\n")
      sh(repo, { "git", "add", "-A" })
      sh(repo, { "git", "commit", "-m", "init" })
      return repo
    end
    local function commit_all(dir, msg)
      sh(dir, { "git", "add", "-A" })
      sh(dir, { "git", "commit", "-m", msg, "--no-verify" })
    end

    -- both sides edit the same line: merge fails rebaseable, root stays pristine
    local repo = mkrepo()
    local wt = worktree.create(repo, "c1")
    local run = { root = repo, worktree = wt.path, branch = wt.branch, base = wt.base, prompt = "p" }
    write(wt.path .. "/README.md", "agent line\n")
    commit_all(wt.path, "agent edit")
    write(repo .. "/README.md", "user line\n")
    commit_all(repo, "user edit")
    local ok, _, meta = worktree.merge(run, "squash")
    check(ok == false and meta ~= nil and meta.rebaseable == true, "conflict: content conflict is rebaseable")
    check(sh(repo, { "git", "status", "--porcelain" }) == "", "conflict: root pristine after aborted merge")
    local sha_before = sh(wt.path, { "git", "rev-parse", "HEAD" })
    local rok, rerr = worktree.rebase_onto_head(run)
    check(
      rok == false and rerr ~= nil and rerr:find("conflict", 1, true) ~= nil,
      "conflict: rebase aborts on real conflicts"
    )
    check(sh(wt.path, { "git", "rev-parse", "HEAD" }) == sha_before, "conflict: branch untouched by aborted rebase")

    -- non-overlapping divergence with ff: rebase then retry succeeds
    local repo2 = mkrepo()
    local wt2 = worktree.create(repo2, "c2")
    local run2 = { root = repo2, worktree = wt2.path, branch = wt2.branch, base = wt2.base, prompt = "p" }
    write(wt2.path .. "/agent.txt", "agent\n")
    commit_all(wt2.path, "agent file")
    write(repo2 .. "/user.txt", "user\n")
    commit_all(repo2, "user file")
    ok, _, meta = worktree.merge(run2, "ff")
    check(ok == false and meta ~= nil and meta.rebaseable == true, "conflict: ff divergence is rebaseable")
    check(worktree.rebase_onto_head(run2) == true, "conflict: rebase onto HEAD succeeds")
    check(run2.base == sh(repo2, { "git", "rev-parse", "HEAD" }), "conflict: run.base moves to the new HEAD")
    check(worktree.merge(run2, "ff") == true, "conflict: retried ff merge succeeds")
    check(
      vim.uv.fs_stat(repo2 .. "/agent.txt") ~= nil and vim.uv.fs_stat(repo2 .. "/user.txt") ~= nil,
      "conflict: both sides' changes land"
    )

    -- the full runner path the dashboard uses (rebase_and_merge on a run record)
    local runner = require("hangar.runner")
    local repo3 = mkrepo()
    local wt3 = worktree.create(repo3, "c3")
    local run3 = {
      id = "c3",
      root = repo3,
      worktree = wt3.path,
      branch = wt3.branch,
      base = wt3.base,
      prompt = "p",
      status = "done",
      started = 1,
      events = {},
    }
    runner.runs.c3 = run3
    write(wt3.path .. "/agent.txt", "agent\n")
    commit_all(wt3.path, "agent file")
    write(repo3 .. "/user.txt", "user\n")
    commit_all(repo3, "user file")
    local mok, _, mmeta = runner.merge("c3", "ff")
    check(mok == false and mmeta and mmeta.rebaseable, "conflict: runner.merge surfaces rebaseable meta")
    check(runner.rebase_and_merge("c3", "ff") == true, "conflict: rebase_and_merge lands the run")
    check(run3.status == "merged", "conflict: run marked merged after rebase-and-retry")
    runner.runs.c3 = nil
  end
end
