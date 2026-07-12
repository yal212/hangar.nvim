---Review a run: changed-file list in a float; <CR> opens a diffsplit of
---base-commit version vs the run's version; merge/discard from here too.
local runner = require("hangar.runner")
local worktree = require("hangar.worktree")

local M = {}

local ns = vim.api.nvim_create_namespace("hangar_review")
require("hangar.ui.hl").define()

local STATUS_HL = { A = "HangarDone", D = "HangarFailed", M = "HangarRunning" }

---Open a diff tab: base version (scratch) | run's worktree file (or branch blob).
local function open_diff(run, file)
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()

  -- right side: the run's version
  local wt_file = run.worktree .. "/" .. file.path
  if vim.uv.fs_stat(wt_file) then
    vim.cmd.edit(vim.fn.fnameescape(wt_file))
  else
    -- worktree gone or file deleted: show branch blob (empty buffer if deleted)
    local blob = {}
    local res = vim.system(
      { "git", "show", run.branch .. ":" .. file.path },
      { cwd = run.root, text = true }
    ):wait()
    if res.code == 0 then
      blob = vim.split(res.stdout, "\n", { plain = true })
    end
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(buf, "hangar://" .. run.branch .. "/" .. file.path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, blob)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = vim.filetype.match({ filename = file.path }) or ""
  end
  vim.cmd.diffthis()

  -- left side: version at the run's base commit
  vim.cmd("leftabove vnew")
  local base_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(base_buf, "hangar://base/" .. file.path)
  local base_content = worktree.show_base(run, file.path)
  vim.api.nvim_buf_set_lines(
    base_buf, 0, -1, false,
    base_content and vim.split(base_content, "\n", { plain = true }) or {}
  )
  vim.bo[base_buf].buftype = "nofile"
  vim.bo[base_buf].modifiable = false
  vim.bo[base_buf].bufhidden = "wipe"
  vim.bo[base_buf].filetype = vim.filetype.match({ filename = file.path }) or ""
  vim.cmd.diffthis()

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = vim.api.nvim_win_get_buf(win), nowait = true })
  end
end

---@param run_id string
function M.open(run_id)
  local run = runner.get(run_id)
  if not run then
    vim.notify("[hangar] no such run: " .. tostring(run_id), vim.log.levels.ERROR)
    return
  end
  local files = worktree.changed_files(run)

  local lines = { "", ("  %s — %d file(s) changed vs %s"):format(run.id, #files, run.base:sub(1, 8)), "" }
  if #files == 0 then
    lines[#lines + 1] = "  (no changes)"
  end
  local first_file_line = #lines + 1
  for _, f in ipairs(files) do
    lines[#lines + 1] = ("  %s  %s"):format(f.status, f.path)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  <CR> diff file   m merge run   x discard run   q back"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hangar_review"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(vim.o.columns - 10, 90)
  local height = math.min(#lines + 2, vim.o.lines - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    style = "minimal",
    border = "rounded",
    title = " review " .. run.id .. " ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #lines[2], hl_group = "HangarHeader" })
  for i, f in ipairs(files) do
    local lnum = first_file_line + i - 2
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 2, {
      end_col = 3,
      hl_group = STATUS_HL[f.status] or "HangarDim",
    })
  end
  vim.api.nvim_buf_set_extmark(buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "HangarDim" })
  if #files > 0 then
    vim.api.nvim_win_set_cursor(win, { first_file_line, 0 })
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function file_under_cursor()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    return files[lnum - first_file_line + 1]
  end
  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  map("q", close)
  map("<Esc>", close)
  map("<CR>", function()
    local f = file_under_cursor()
    if f then
      close()
      open_diff(run, f)
    end
  end)
  map("m", function()
    local strategy = require("hangar").config.merge
    if vim.fn.confirm(("Merge %s (%s)?"):format(run.id, strategy), "&Yes\n&No", 2) ~= 1 then
      return
    end
    local ok, err = runner.merge(run.id)
    close()
    if ok then
      vim.notify(("[hangar] merged %s"):format(run.id))
    else
      vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
    end
  end)
  map("x", function()
    if vim.fn.confirm(("Discard %s? Worktree and branch are deleted."):format(run.id), "&Yes\n&No", 2) ~= 1 then
      return
    end
    local ok, err = runner.discard(run.id)
    close()
    if not ok then
      vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
    end
  end)
end

return M
