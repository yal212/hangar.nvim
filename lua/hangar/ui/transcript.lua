---Streaming transcript tail: pretty-prints a run's parsed events into a
---split and follows the tail while the cursor stays at the bottom.
local util = require("hangar.util")
local runner = require("hangar.runner")

local M = {}

require("hangar.ui.hl").define()

local ns = vim.api.nvim_create_namespace("hangar_transcript")

---Render one event as (lines, hl_group|nil). Multi-line text is split.
---@param ev hangar.Event
---@return string[] lines
---@return string|nil hl_group applied to every line, when the kind has one
local function event_lines(ev)
  if ev.kind == "text" then
    return vim.split(ev.text, "\n", { plain = true }), nil
  elseif ev.kind == "tool_use" then
    local s = ev.summary ~= "" and (" " .. ev.summary) or ""
    return { ("⚒ %s%s"):format(ev.tool, s) }, "HangarToolUse"
  elseif ev.kind == "tool_result" then
    local prefix = ev.is_error and "✗ " or "→ "
    return { "  " .. prefix .. ev.text }, ev.is_error and "HangarFailed" or "HangarDim"
  elseif ev.kind == "result" then
    local parts = { ev.is_error and "✗ finished with error" or "✓ finished" }
    if ev.turns then
      parts[#parts + 1] = ev.turns .. " turns"
    end
    if ev.cost then
      parts[#parts + 1] = ("$%.4f"):format(ev.cost)
    end
    if ev.duration_ms then
      parts[#parts + 1] = ("%.0fs"):format(ev.duration_ms / 1000)
    end
    return { "", table.concat(parts, "  ·  ") }, ev.is_error and "HangarFailed" or "HangarDone"
  end
  return {}, nil
end

---Buffers currently tailing, keyed by run id.
local open_bufs = {}

---Redraw the whole transcript buffer from the run's event list, then follow
---the tail in any window whose cursor is still at the bottom.
---@param buf integer
---@param run hangar.Run
local function render_all(buf, run)
  -- the prompt is a one-line header, and nvim_buf_set_lines rejects a line
  -- containing a newline — which an iterated run's prompt always has (see
  -- runner._iterate_prompt). The dashboard and the pickers collapse it the
  -- same way; only assistant prose is deliberately rendered across lines.
  local lines = { ("prompt: %s"):format((run.prompt:gsub("%s+", " "))), "" }
  local marks = { { line = 0, hl = "HangarDim" } }
  for _, ev in ipairs(run.events) do
    local evl, hl = event_lines(ev)
    for _, l in ipairs(evl) do
      lines[#lines + 1] = l
      if hl then
        marks[#marks + 1] = { line = #lines - 1, hl = hl }
      end
    end
  end
  if run.status == "running" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "● running…"
    marks[#marks + 1] = { line = #lines - 1, hl = "HangarRunning" }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local text = lines[m.line + 1]
    if text and text ~= "" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { end_col = #text, hl_group = m.hl })
    end
  end

  -- follow tail in windows whose cursor is at (or past) the old bottom
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    if cur >= vim.api.nvim_buf_line_count(buf) - 3 then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

---@param run_id string
function M.open(run_id)
  local run = runner.get(run_id)
  if not run then
    util.notify_err("no such run: " .. tostring(run_id))
    return
  end

  local existing = open_bufs[run_id]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    local wins = vim.fn.win_findbuf(existing)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
    else
      vim.cmd("botright split")
      vim.api.nvim_set_current_buf(existing)
    end
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  open_bufs[run_id] = buf
  vim.api.nvim_buf_set_name(buf, "hangar://transcript/" .. run_id)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hangar_transcript"

  vim.cmd("botright split")
  vim.api.nvim_set_current_buf(buf)
  vim.wo[0].wrap = true
  vim.wo[0].linebreak = true

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })

  local group = vim.api.nvim_create_augroup("HangarTranscript_" .. run_id, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "HangarRunUpdate",
    callback = function(ev)
      if not vim.api.nvim_buf_is_valid(buf) then
        open_bufs[run_id] = nil
        return true -- delete autocmd
      end
      if ev.data and ev.data.id == run_id then
        local current = runner.get(run_id)
        if not current then
          -- discarded while open: keep what is shown, say so, stop following
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", ("run %s was discarded"):format(run_id) })
          vim.bo[buf].modifiable = false
          local last = vim.api.nvim_buf_line_count(buf) - 1
          vim.api.nvim_buf_set_extmark(buf, ns, last, 0, { end_row = last + 1, hl_group = "HangarDim" })
          open_bufs[run_id] = nil
          return true -- delete autocmd
        end
        render_all(buf, current)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      open_bufs[run_id] = nil
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })

  render_all(buf, run)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
end

return M
