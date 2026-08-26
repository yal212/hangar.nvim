---Dashboard actions, called directly with a run — no window involved.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  local actions = require("hangar.ui.actions")
  local runner = require("hangar.runner")

  local repo = harness.git_repo("actions")
  sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
  local prev = assert(vim.uv.cwd())
  vim.fn.chdir(repo)
  local root = require("hangar.worktree").root()

  -- capture notifications instead of printing them
  local orig_notify = vim.notify
  local msgs, levels
  local function capture()
    msgs, levels = {}, {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(m, l)
      msgs[#msgs + 1] = m
      levels[#levels + 1] = l
    end
  end
  local function restore()
    vim.notify = orig_notify
  end
  local function said(needle)
    for _, m in ipairs(msgs or {}) do
      if type(m) == "string" and m:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  -- stub the blocking prompts
  local orig_confirm, orig_input, orig_select = vim.fn.confirm, vim.ui.input, vim.ui.select
  local confirm_answer, confirm_prompts
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.confirm = function(prompt)
    confirm_prompts[#confirm_prompts + 1] = prompt
    return confirm_answer
  end
  local input_answer
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.input = function(_, cb)
    cb(input_answer)
  end

  local function mk(id, fields)
    local run = vim.tbl_extend("force", {
      id = id,
      root = root,
      status = "done",
      started = os.time(),
      events = {},
      prompt = "p",
    }, fields or {})
    runner.runs[id] = run
    return run
  end

  -- discardable_siblings: only non-running, non-merged members of the same group
  check(#actions.discardable_siblings(mk("a1")) == 0, "actions: ungrouped run has no siblings")
  local g1 = mk("g1", { group = "g", attempt = 1, status = "merged" })
  mk("g2", { group = "g", attempt = 2, status = "done" })
  mk("g3", { group = "g", attempt = 3, status = "running" })
  mk("g4", { group = "g", attempt = 4, status = "merged" })
  mk("g5", { group = "other", attempt = 1, status = "done" })
  local sibs = actions.discardable_siblings(g1)
  check(#sibs == 1 and sibs[1].id == "g2", "actions: siblings exclude self, running, merged and other groups")

  -- kill surfaces the runner's error rather than throwing
  capture()
  actions.kill(mk("k1", { status = "done" }))
  restore()
  check(said("not running") or said("k1"), "actions: kill reports why a finished run cannot be killed")
  check(levels[1] == vim.log.levels.ERROR, "actions: kill errors at ERROR level")

  -- declining the confirm leaves the run alone
  confirm_answer, confirm_prompts = 2, {}
  capture()
  actions.discard(mk("d1"))
  restore()
  check(runner.runs["d1"] ~= nil, "actions: discard declined leaves the run in the registry")
  check(#confirm_prompts == 1 and confirm_prompts[1]:find("d1", 1, true) ~= nil, "actions: discard confirms first")
  check(#msgs == 0, "actions: discard declined says nothing")

  -- accepting it removes the run
  confirm_answer, confirm_prompts = 1, {}
  capture()
  actions.discard(runner.runs["d1"])
  restore()
  check(runner.runs["d1"] == nil, "actions: discard accepted drops the run")

  -- merge asks before touching the branch, and declining is a no-op
  confirm_answer, confirm_prompts = 2, {}
  capture()
  actions.merge(mk("m1"))
  restore()
  check(#confirm_prompts == 1 and confirm_prompts[1]:find("Merge m1", 1, true) ~= nil, "actions: merge confirms first")
  check(runner.runs["m1"].status == "done", "actions: merge declined leaves status untouched")
  check(#msgs == 0, "actions: merge declined says nothing")

  -- empty feedback cancels an iteration before the runner is called
  input_answer = "   "
  capture()
  actions.iterate(mk("i1"))
  restore()
  check(#msgs == 0, "actions: iterate with blank feedback is a no-op")

  -- resume refuses a run that is not orphaned, and says so
  capture()
  actions.resume(mk("r1", { status = "done" }))
  restore()
  check(said("r1") and levels[1] == vim.log.levels.ERROR, "actions: resume reports why a done run cannot resume")

  -- a queued run has no base commit yet: review must refuse instead of throwing,
  -- and must not close the dashboard on the way out
  capture()
  local ok = pcall(actions.review, mk("q1", { status = "queued" }))
  restore()
  check(ok, "actions: review of a queued run does not throw")
  check(said("has not started yet"), "actions: review says a queued run has not started")
  check(vim.bo.filetype ~= "hangar_review", "actions: review of a queued run opens nothing")

  -- ...while a started run still opens the review float
  local head = sh(repo, { "git", "rev-parse", "HEAD" })
  capture()
  actions.review(mk("v1", { base = head, branch = "main", worktree = repo }))
  restore()
  check(vim.bo.filetype == "hangar_review", "actions: review of a started run opens the float")
  vim.api.nvim_win_close(0, true)

  -- spawn with an empty prompt never reaches the runner
  input_answer = ""
  local before = vim.tbl_count(runner.runs)
  capture()
  actions.spawn()
  restore()
  check(vim.tbl_count(runner.runs) == before, "actions: spawn with a blank prompt creates nothing")

  vim.fn.confirm, vim.ui.input, vim.ui.select = orig_confirm, orig_input, orig_select
  for id in pairs(runner.runs) do
    if id:match("^[adgkmirqv]%d$") then
      runner.runs[id] = nil
    end
  end
  vim.fn.chdir(prev)
end
