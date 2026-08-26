---fzf-lua entry point: `require("hangar.pickers.fzf").runs()`.
---<CR> transcript · <C-d> review/diff · <C-e> iterate · <C-x> discard.
local util = require("hangar.util")
local M = {}

function M.runs(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    util.notify_err("fzf-lua is not installed")
    return
  end
  local hangar_pickers = require("hangar.pickers")
  local entries, err = hangar_pickers.entries()
  if not entries then
    util.notify_err(err)
    return
  end

  local by_display = {}
  local lines = {}
  for _, entry in ipairs(entries) do
    by_display[entry.display] = entry.run
    lines[#lines + 1] = entry.display
  end

  local function run_of(selected)
    return selected and selected[1] and by_display[selected[1]] or nil
  end

  local actions = {}
  for _, action in ipairs(hangar_pickers.actions) do
    actions[action.fzf] = function(selected)
      local run = run_of(selected)
      if run then
        action.run(run.id)
      end
    end
  end

  fzf.fzf_exec(lines, vim.tbl_deep_extend("force", { prompt = "hangar runs> ", actions = actions }, opts or {}))
end

return M
