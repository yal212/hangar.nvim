---Telescope extension: `:Telescope hangar runs`.
---<CR> transcript · <C-d> review/diff · <C-x> discard.
local ok, telescope = pcall(require, "telescope")
if not ok then
  error("hangar.nvim picker requires telescope.nvim")
end

local function runs_picker(opts)
  opts = opts or {}
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local hangar_pickers = require("hangar.pickers")

  local entries, err = hangar_pickers.entries()
  if not entries then
    vim.notify("[hangar] " .. err, vim.log.levels.ERROR)
    return
  end

  local function selected_run(prompt_bufnr, close)
    local entry = action_state.get_selected_entry()
    if close then
      actions.close(prompt_bufnr)
    end
    return entry and entry.value.run or nil
  end

  pickers
    .new(opts, {
      prompt_title = "hangar runs",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = ("%s %s %s"):format(entry.run.id, entry.run.status, entry.run.prompt),
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local run = selected_run(prompt_bufnr, true)
          if run then
            hangar_pickers.open_transcript(run.id)
          end
        end)
        map({ "i", "n" }, "<C-d>", function()
          local run = selected_run(prompt_bufnr, true)
          if run then
            hangar_pickers.open_review(run.id)
          end
        end)
        map({ "i", "n" }, "<C-x>", function()
          local run = selected_run(prompt_bufnr, true)
          if run then
            hangar_pickers.discard(run.id)
          end
        end)
        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    hangar = runs_picker, -- `:Telescope hangar`
    runs = runs_picker, -- `:Telescope hangar runs`
  },
})
