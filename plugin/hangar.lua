if vim.g.loaded_hangar then
  return
end
vim.g.loaded_hangar = true

vim.api.nvim_create_user_command("Hangar", function(cmd)
  require("hangar")._command(cmd)
end, {
  nargs = "*",
  desc = "Agent mission control: spawn/monitor/merge parallel agent runs",
  complete = function(arg_lead, cmd_line)
    return require("hangar")._complete(arg_lead, cmd_line)
  end,
})
