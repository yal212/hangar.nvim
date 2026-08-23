-- Minimal Neovim config for the demo recording (assets/demo.tape).
-- Nothing here changes plugin behaviour: the only hangar setting is the
-- adapter `cmd` override that points the real claude_code adapter at the
-- scripted stub in assets/demo/fake-claude.

local root = assert(os.getenv("HANGAR_DEMO_ROOT"), "source assets/demo/seed-repo.sh first")
vim.opt.runtimepath:prepend(root)

-- recording hygiene
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.number = false
vim.opt.shortmess:append("I") -- no intro splash
vim.opt.laststatus = 0
vim.opt.ruler = false
vim.opt.showmode = false
vim.opt.fillchars = { eob = " " }
vim.opt.termguicolors = true
vim.cmd.colorscheme("habamax")

require("hangar").setup({
  adapters = { claude_code = { cmd = root .. "/assets/demo/fake-claude" } },
})
