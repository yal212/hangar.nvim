# hangar.nvim

**Run a fleet of coding agents in parallel git worktrees. Review and merge from a dashboard.**

Spawn multiple headless [Claude Code](https://claude.com/claude-code) runs on different tasks — each in its own git worktree and branch — watch them work live, diff the results, merge the winners, discard the rest. Never leave Neovim.

*Think: lazygit for coding agents.*

<!-- demo GIF goes here -->

## Why

Power users already do this by hand: `tmux` panes, `git worktree add`, `claude -p "..."` in each, then juggle diffs and merges. hangar.nvim turns that workflow into three keystrokes:

```
:Hangar spawn --yolo fix the flaky auth test
:Hangar spawn --yolo add dark mode to the settings page
:Hangar          " dashboard: watch both, diff, merge the good one
```

- **Parallel by default** — each run gets an isolated worktree + branch under `.hangar/`; your working tree is never touched.
- **Live mission control** — dashboard shows status, elapsed time, model, turn count, cost, and files changed for every run, updating in real time.
- **Readable transcripts** — `<CR>` tails a run's stream as clean text and tool calls, not raw JSON.
- **Native review** — `d` lists changed files; `<CR>` opens a real `diffsplit` against the run's base commit. `m` squash-merges the branch, `x` deletes worktree + branch.
- **Zero dependencies** — pure Lua, no plenary, Neovim ≥ 0.10. Requires `git` and the `claude` CLI.

## Install

lazy.nvim:

```lua
{
  "yal212/hangar.nvim",
  cmd = "Hangar",
  opts = {},
}
```

## Usage

| Command | |
|---|---|
| `:Hangar` | open the dashboard |
| `:Hangar spawn --yolo <prompt>` | spawn an agent with full tool access (runs sandboxed in its worktree) |
| `:Hangar spawn --safe <prompt>` | spawn an agent that can edit files but not run shell commands |
| `:Hangar spawn --model haiku <prompt>` | pick a model per run |
| `:Hangar kill <id>` | stop a running agent |
| `:Hangar clean` | delete worktrees/branches of all finished runs |

Dashboard keys: `<CR>` transcript · `d` review/diff · `m` merge · `x` discard · `K` kill · `s` spawn · `r` refresh · `q` quit.

Every spawn needs an explicit `--yolo` or `--safe` — headless agents can't answer permission prompts, so you choose the blast radius per run. If you always want one mode:

```lua
opts = { default_permission = "yolo" }
```

## Configuration

```lua
require("hangar").setup({
  default_permission = nil,  -- "yolo" | "safe" | nil (require an explicit flag per spawn)
  merge = "squash",          -- "squash" | "ff" | "merge"
  model = nil,               -- default model for spawns, e.g. "haiku"
  claude_cmd = "claude",     -- path to the Claude Code CLI
})
```

Lua API: `require("hangar").spawn(prompt, { permission_mode = "bypassPermissions", model = "haiku" })`.

## How it works

`:Hangar spawn` creates `.hangar/worktrees/<id>` on branch `hangar/<id>` (excluded from git status automatically), then runs `claude -p <prompt> --output-format stream-json` there via `vim.system`. Events stream into the run registry and every open UI updates through a `User HangarRunUpdate` autocmd. When a run finishes with uncommitted changes, hangar commits them so the branch is always mergeable. State persists to `stdpath("data")/hangar/runs.json`, so finished runs survive restarting Neovim.

Adapters are a small contract (`build_cmd`, `parse_line`) — see `lua/hangar/adapters/claude_code.lua`. Codex / Gemini / OpenCode adapters are welcome contributions.

## Tests

```sh
# parser + arg handling (offline, free)
nvim --headless -l tests/run_tests.lua

# full end-to-end with a real claude run (costs a few cents)
XDG_DATA_HOME=$(mktemp -d) nvim --headless -l tests/run_tests.lua --integration
```

## License

MIT
