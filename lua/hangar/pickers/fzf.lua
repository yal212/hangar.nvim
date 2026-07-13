---fzf-lua entry point: `require("hangar.pickers.fzf").runs()`.
---<CR> transcript · <C-d> review/diff · <C-x> discard.
local M = {}

function M.runs(opts)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("[hangar] fzf-lua is not installed", vim.log.levels.ERROR)
    return
  end
  local hangar_pickers = require("hangar.pickers")
  local entries, err = hangar_pickers.entries()
  if not entries then
    vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
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

  fzf.fzf_exec(
    lines,
    vim.tbl_deep_extend("force", {
      prompt = "hangar runs> ",
      actions = {
        ["default"] = function(selected)
          local run = run_of(selected)
          if run then
            hangar_pickers.open_transcript(run.id)
          end
        end,
        ["ctrl-d"] = function(selected)
          local run = run_of(selected)
          if run then
            hangar_pickers.open_review(run.id)
          end
        end,
        ["ctrl-x"] = function(selected)
          local run = run_of(selected)
          if run then
            hangar_pickers.discard(run.id)
          end
        end,
      },
    }, opts or {})
  )
end

return M
