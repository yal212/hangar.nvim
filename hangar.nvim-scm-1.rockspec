-- luarocks / rocks.nvim packaging. `scm-1` tracks main; tagged releases are
-- published as hangar.nvim-X.Y.Z-1.rockspec with a matching source.tag.
rockspec_format = "3.0"
package = "hangar.nvim"
version = "scm-1"

source = {
  url = "git+https://github.com/yal212/hangar.nvim",
  branch = "main",
}

description = {
  summary = "Run a fleet of coding agents in parallel git worktrees.",
  detailed = [[
    hangar.nvim spawns headless coding-agent runs — Claude Code, OpenAI Codex,
    Gemini CLI or OpenCode — each in its own git worktree and branch. A live
    dashboard shows status, cost and changed files; review a run's diff, merge
    the winners and discard the rest without leaving Neovim.
  ]],
  homepage = "https://github.com/yal212/hangar.nvim",
  license = "MIT",
  labels = { "neovim", "agents", "git-worktree" },
}

-- No runtime dependencies: hangar uses only Neovim's own vim.system/vim.uv.
dependencies = { "lua >= 5.1" }

build = {
  type = "builtin",
  copy_directories = { "doc", "plugin" },
}
