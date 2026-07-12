---Floating dashboard: one row per run, live-updating via HangarRunUpdate.
local runner = require("hangar.runner")
local worktree = require("hangar.worktree")

local M = {}

local ns = vim.api.nvim_create_namespace("hangar_dashboard")

local STATUS = {
  running = { icon = "●", hl = "HangarRunning" },
  done = { icon = "✓", hl = "HangarDone" },
  failed = { icon = "✗", hl = "HangarFailed" },
  killed = { icon = "⊘", hl = "HangarFailed" },
  merged = { icon = "⇡", hl = "HangarMerged" },
  orphaned = { icon = "?", hl = "HangarOrphaned" },
}

local define_highlights = require("hangar.ui.hl").define

---Dashboard state for the single open instance.
local state = {
  buf = nil,
  win = nil,
  root = nil,
  timer = nil,
  line_runs = {}, -- 1-indexed buffer line -> run id
  files_cache = {}, -- run id -> file count (refreshed on run updates, not ticks)
}

local function is_open()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function fmt_elapsed(run)
  local stop = run.finished or os.time()
  local secs = math.max(0, stop - (run.started or stop))
  return ("%02d:%02d"):format(math.floor(secs / 60), secs % 60)
end

local function short_model(model)
  if not model or model == vim.NIL then
    return "-"
  end
  return (model:gsub("^claude%-", ""):gsub("%-%d%d%d%d%d%d%d%d$", ""))
end

local function files_count(run, refresh)
  if refresh or state.files_cache[run.id] == nil then
    local ok, files = pcall(worktree.changed_files, run)
    state.files_cache[run.id] = ok and #files or 0
  end
  return state.files_cache[run.id]
end

---@param refresh_files boolean whether to re-run git for the files column
function M.render(refresh_files)
  if not is_open() then
    return
  end
  local runs = runner.list(state.root)
  local lines, marks = {}, {}
  state.line_runs = {}

  lines[1] = ""
  lines[2] = ("  %-1s %-9s %-7s %-10s %5s %8s %5s  %s"):format(
    " ", "run", "time", "model", "turns", "cost", "files", "prompt"
  )
  marks[#marks + 1] = { line = 1, col = 0, end_col = #lines[2], hl = "HangarHeader" }

  if #runs == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  No runs yet.  Spawn one:  :Hangar spawn --yolo <prompt>   (or press s)"
    marks[#marks + 1] = { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "HangarDim" }
  end

  for _, run in ipairs(runs) do
    local st = STATUS[run.status] or { icon = " ", hl = "HangarDim" }
    local prompt = run.prompt:gsub("%s+", " ")
    local row = ("  %s %-9s %-7s %-10s %5s %8s %5s  %s"):format(
      st.icon,
      run.id,
      fmt_elapsed(run),
      short_model(run.model),
      run.turns or "-",
      run.cost and ("$%.2f"):format(run.cost) or "-",
      files_count(run, refresh_files) or "-",
      prompt:sub(1, 50) .. (#prompt > 50 and "…" or "")
    )
    lines[#lines + 1] = row
    state.line_runs[#lines] = run.id
    marks[#marks + 1] = { line = #lines - 1, col = 2, end_col = 2 + #st.icon, hl = st.hl }
  end

  lines[#lines + 1] = ""
  local hint = "  <CR> transcript   d diff   m merge   x discard   K kill   s spawn   q quit"
  lines[#lines + 1] = hint
  marks[#marks + 1] = { line = #lines - 1, col = 0, end_col = #hint, hl = "HangarDim" }

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, m.line, m.col, { end_col = m.end_col, hl_group = m.hl })
  end
end

local function run_under_cursor()
  if not is_open() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  local id = state.line_runs[lnum]
  return id and runner.get(id) or nil
end

function M.close()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

local function notify_err(msg)
  vim.notify("[hangar] " .. msg, vim.log.levels.ERROR)
end

local function action_transcript()
  local run = run_under_cursor()
  if run then
    M.close()
    require("hangar.ui.transcript").open(run.id)
  end
end

local function action_review()
  local run = run_under_cursor()
  if run then
    M.close()
    require("hangar.ui.review").open(run.id)
  end
end

local function action_merge()
  local run = run_under_cursor()
  if not run then
    return
  end
  local strategy = require("hangar").config.merge
  local choice = vim.fn.confirm(("Merge %s (%s) into your branch?"):format(run.id, strategy), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local ok, err = runner.merge(run.id)
  if ok then
    vim.notify(("[hangar] merged %s"):format(run.id))
  else
    notify_err(err)
  end
end

local function action_discard()
  local run = run_under_cursor()
  if not run then
    return
  end
  local choice = vim.fn.confirm(("Discard %s? Worktree and branch are deleted."):format(run.id), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local ok, err = runner.discard(run.id)
  if not ok then
    notify_err(err)
  end
end

local function action_kill()
  local run = run_under_cursor()
  if not run then
    return
  end
  local ok, err = runner.kill(run.id)
  if not ok then
    notify_err(err)
  end
end

local function action_spawn()
  vim.ui.input({ prompt = "Agent prompt: " }, function(prompt)
    if not prompt or vim.trim(prompt) == "" then
      return
    end
    local hangar = require("hangar")
    if hangar.config.default_permission then
      hangar.spawn(prompt)
      return
    end
    vim.ui.select({ "yolo (full tool access)", "safe (edits only, no shell)" }, {
      prompt = "Permission mode for this run:",
    }, function(choice)
      if not choice then
        return
      end
      local mode = choice:match("^yolo") and "bypassPermissions" or "acceptEdits"
      hangar.spawn(prompt, { permission_mode = mode })
    end)
  end)
end

function M.open()
  local root, err = worktree.root()
  if not root then
    notify_err(err)
    return
  end
  if is_open() then
    vim.api.nvim_set_current_win(state.win)
    return
  end
  define_highlights()
  state.root = root
  state.files_cache = {}

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "hangar"

  local width = math.min(vim.o.columns - 6, 110)
  local height = math.min(math.max(#runner.list(root) + 5, 7), vim.o.lines - 6)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    style = "minimal",
    border = "rounded",
    title = " hangar — " .. vim.fn.fnamemodify(root, ":t") .. " ",
    title_pos = "center",
  })
  vim.wo[state.win].cursorline = true

  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true })
  end
  map("q", M.close)
  map("<Esc>", M.close)
  map("<CR>", action_transcript)
  map("d", action_review)
  map("m", action_merge)
  map("x", action_discard)
  map("K", action_kill)
  map("s", action_spawn)
  map("r", function()
    M.render(true)
  end)

  local group = vim.api.nvim_create_augroup("HangarDashboard", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "HangarRunUpdate",
    callback = function()
      if is_open() then
        M.render(true)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(state.win),
    once = true,
    callback = M.close,
  })

  -- 1s tick keeps elapsed times moving while any run is live; skips git calls
  state.timer = assert(vim.uv.new_timer())
  state.timer:start(1000, 1000, vim.schedule_wrap(function()
    if is_open() then
      M.render(false)
    end
  end))

  M.render(true)
end

return M
