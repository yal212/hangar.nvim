---Dashboard rendering: turns the run registry into buffer lines plus highlight
---extmarks. Split out of dashboard.lua so the display logic can be exercised
---without opening a window — everything here takes `state` explicitly and owns
---no mutable state of its own.
local worktree = require("hangar.worktree")
local runner = require("hangar.runner")
local icons = require("hangar.ui.icons")

local M = {}

local ns = vim.api.nvim_create_namespace("hangar_dashboard")

---Short adapter name for the dashboard column.
local ADAPTER_NAMES = { claude_code = "claude" }

---Sort rank for the "status" ordering: live work first, merged last.
local STATUS_RANK =
  { running = 1, detached = 2, queued = 3, done = 4, failed = 5, orphaned = 6, killed = 7, merged = 8 }

---Row ordering cycle, driven by the dashboard's `o` key.
M.NEXT_SORT = { recent = "status", status = "cost", cost = "recent" }

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

local function files_count(state, run, refresh)
  if refresh or state.files_cache[run.id] == nil then
    local ok, files = pcall(worktree.changed_files, run)
    state.files_cache[run.id] = ok and #files or 0
  end
  return state.files_cache[run.id]
end

---@param refresh_files boolean whether to re-run git for the files column
function M.render(state, refresh_files)
  local all_runs = runner.list(state.root)
  local runs = state.hide_merged and vim.tbl_filter(function(r)
    return r.status ~= "merged"
  end, all_runs) or all_runs
  local lines, marks = {}, {}
  state.line_runs = {}

  lines[1] = ""
  lines[2] = ("  %-1s %-9s %-8s %-7s %-10s %5s %8s %5s  %s"):format(
    " ",
    "run",
    "adapter",
    "time",
    "model",
    "turns",
    "cost",
    "files",
    "prompt"
  )
  marks[#marks + 1] = { line = 1, col = 0, end_col = #lines[2], hl = "HangarHeader" }

  if #runs == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  No runs yet.  Spawn one:  :Hangar spawn --yolo <prompt>   (or press s)"
    marks[#marks + 1] = { line = #lines - 1, col = 0, end_col = #lines[#lines], hl = "HangarDim" }
  end

  local function add_row(run, prompt_text)
    local st = icons.get(run.status)
    local row = ("  %s %-9s %-8s %-7s %-10s %5s %8s %5s  %s"):format(
      st.icon,
      run.id,
      ADAPTER_NAMES[run.adapter] or run.adapter or "-",
      fmt_elapsed(run),
      short_model(run.model),
      run.turns or "-",
      run.cost and ("$%.2f"):format(run.cost) or "-",
      files_count(state, run, refresh_files) or "-",
      prompt_text
    )
    lines[#lines + 1] = row
    state.line_runs[#lines] = run.id
    marks[#marks + 1] = { line = #lines - 1, col = 2, end_col = 2 + #st.icon, hl = st.hl }
  end

  local function clip(prompt, max)
    prompt = prompt:gsub("%s+", " ")
    return prompt:sub(1, max) .. (#prompt > max and "…" or "")
  end

  -- display units: single runs, or one unit per best-of-n / iteration group
  -- (groups always render as a block, whatever the sort order)
  local units, by_group = {}, {}
  for _, run in ipairs(runs) do
    if not run.group then
      units[#units + 1] = { runs = { run } }
    elseif by_group[run.group] then
      table.insert(by_group[run.group].runs, run)
    else
      local unit = { runs = { run }, group = run.group }
      by_group[run.group] = unit
      units[#units + 1] = unit
    end
  end

  local function unit_key(unit)
    local newest, rank, cost = 0, 99, nil
    for _, r in ipairs(unit.runs) do
      newest = math.max(newest, r.started or 0)
      rank = math.min(rank, STATUS_RANK[r.status] or 9)
      if r.cost then
        cost = (cost or 0) + r.cost
      end
    end
    return newest, rank, cost
  end
  if state.sort ~= "recent" then -- units arrive newest-first already
    table.sort(units, function(a, b)
      local an, ar, ac = unit_key(a)
      local bn, br, bc = unit_key(b)
      if state.sort == "status" and ar ~= br then
        return ar < br
      end
      if state.sort == "cost" and (ac or -1) ~= (bc or -1) then
        return (ac or -1) > (bc or -1)
      end
      return an > bn
    end)
  end

  for _, unit in ipairs(units) do
    if not unit.group then
      add_row(unit.runs[1], clip(unit.runs[1].prompt, 42))
    else
      table.sort(unit.runs, function(a, b)
        return (a.attempt or 0) < (b.attempt or 0)
      end)
      local header = ("  %d× %s"):format(#unit.runs, clip(unit.runs[1].prompt, 70))
      lines[#lines + 1] = header
      marks[#marks + 1] = { line = #lines - 1, col = 0, end_col = #header, hl = "HangarDim" }
      for _, member in ipairs(unit.runs) do
        add_row(member, ("↳ attempt %d"):format(member.attempt or 0))
      end
    end
  end

  -- totals footer (always over the full run list, filter or not)
  local totals = { running = 0, queued = 0, cost = nil }
  for _, run in ipairs(all_runs) do
    if run.status == "running" then
      totals.running = totals.running + 1
    elseif run.status == "queued" then
      totals.queued = totals.queued + 1
    end
    if run.cost then
      totals.cost = (totals.cost or 0) + run.cost
    end
  end
  if #all_runs > 0 then
    local fparts = { totals.running .. " running" }
    if totals.queued > 0 then
      fparts[#fparts + 1] = totals.queued .. " queued"
    end
    if totals.cost then
      fparts[#fparts + 1] = ("total $%.2f"):format(totals.cost)
    end
    if state.sort ~= "recent" then
      fparts[#fparts + 1] = "sort: " .. state.sort
    end
    if state.hide_merged then
      fparts[#fparts + 1] = "[merged hidden]"
    end
    lines[#lines + 1] = ""
    local footer = "  " .. table.concat(fparts, " · ")
    lines[#lines + 1] = footer
    marks[#marks + 1] = { line = #lines - 1, col = 0, end_col = #footer, hl = "HangarDim" }
  end

  lines[#lines + 1] = ""
  local hint =
    "  <CR> transcript  d diff  m merge  x discard  i iterate  K kill  R resume  s spawn  o sort  f filter  q quit"
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

return M
