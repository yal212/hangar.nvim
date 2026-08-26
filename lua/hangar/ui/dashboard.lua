---Floating dashboard: one row per run, live-updating via HangarRunUpdate.
---
---This module owns the window and the keymaps only. Rows are built by
---|hangar.ui.render| and the keys dispatch into |hangar.ui.actions|.
local util = require("hangar.util")
local runner = require("hangar.runner")
local worktree = require("hangar.worktree")
local render = require("hangar.ui.render")
local actions = require("hangar.ui.actions")

local M = {}

local define_highlights = require("hangar.ui.hl").define

---Dashboard state for the single open instance.
---@class hangar.DashboardState
---@field buf integer|nil
---@field win integer|nil
---@field root string|nil
---@field timer uv.uv_timer_t|nil
---@field line_runs table<integer, string>
---@field files_cache table<string, integer>
---@field sort "recent"|"status"|"cost"
---@field hide_merged boolean
local state = {
  buf = nil,
  win = nil,
  root = nil,
  timer = nil,
  line_runs = {}, -- 1-indexed buffer line -> run id
  files_cache = {}, -- run id -> file count (refreshed on run updates, not ticks)
  sort = "recent", -- "recent"|"status"|"cost"
  hide_merged = false,
}

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---Whether the dashboard float is currently visible (used by the runner to
---suppress completion notifications the dashboard already shows live).
function M.is_open()
  return is_open()
end

---@param refresh_files boolean whether to re-run git for the files column
function M.render(refresh_files)
  if not is_open() then
    return
  end
  render.render(state, refresh_files)
end

---Cycle the row ordering: recent (default) -> status -> cost.
function M.cycle_sort()
  state.sort = render.NEXT_SORT[state.sort] or "recent"
  M.render(false)
end

---Show/hide merged runs.
function M.toggle_merged()
  state.hide_merged = not state.hide_merged
  M.render(false)
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

---Wrap a run-taking action as a keymap callback: resolve the row under the
---cursor first, and do nothing on a header, footer or blank line.
---@param action fun(run: hangar.Run)
local function on_run(action)
  return function()
    local run = run_under_cursor()
    if run then
      action(run)
    end
  end
end

function M.open()
  local root, err = worktree.root()
  if not root then
    util.notify_err(err)
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
  map("<CR>", on_run(actions.transcript))
  map("d", on_run(actions.review))
  map("m", on_run(actions.merge))
  map("x", on_run(actions.discard))
  map("K", on_run(actions.kill))
  map("R", on_run(actions.resume))
  map("i", on_run(actions.iterate))
  map("s", actions.spawn)
  map("o", M.cycle_sort)
  map("f", M.toggle_merged)
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
  state.timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if is_open() then
        M.render(false)
      end
    end)
  )

  M.render(true)
end

return M
