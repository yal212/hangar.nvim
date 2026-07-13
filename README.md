# hangar.nvim

[![CI](https://github.com/yal212/hangar.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/yal212/hangar.nvim/actions/workflows/ci.yml)

**Run a fleet of coding agents in parallel git worktrees. Review and merge from a dashboard.**

Spawn headless agent runs — [Claude Code](https://claude.com/claude-code) (default), OpenAI Codex, Gemini CLI, or OpenCode — on different tasks, each in its own git worktree and branch. Watch them work live, diff the results, merge the winners, discard the rest. Never leave Neovim.

*Think: lazygit for coding agents.*

<!-- demo GIF goes here -->

## Why

Power users already do this by hand: `tmux` panes, `git worktree add`, `claude -p "..."` in each, then juggle diffs and merges. hangar.nvim turns that workflow into three keystrokes:

```
:Hangar spawn --yolo fix the flaky auth test
:Hangar spawn --yolo add dark mode to the settings page
:Hangar          " dashboard: watch both, diff, merge the good one
```

- **Parallel by default** — each run gets an isolated worktree + branch outside your repo; your working tree is never touched.
- **Live mission control** — dashboard shows status, adapter, elapsed time, model, turn count, cost, and files changed for every run, with repo totals in the footer, sort and filter toggles, all updating in real time.
- **Readable transcripts** — `<CR>` tails a run's stream as clean text and tool calls, not raw JSON.
- **Native review** — `d` lists changed files; `<CR>` opens a real `diffsplit` against the run's base commit. `m` squash-merges the branch (offering a rebase-and-retry when it conflicts), `x` deletes worktree + branch.
- **Zero dependencies** — pure Lua, no plenary, Neovim ≥ 0.10. Requires `git` and at least one agent CLI (`claude` by default).

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
| `:Hangar spawn --safe <prompt>` | spawn an agent with reduced permissions (exact mapping is per adapter, see below) |
| `:Hangar spawn --model haiku <prompt>` | pick a model per run |
| `:Hangar spawn --adapter codex <prompt>` | pick an agent CLI per run (`claude_code`, `codex`, `gemini`, `opencode`) |
| `:Hangar spawn --n 3 --yolo <prompt>` | best-of-3: three attempts of the same prompt in parallel worktrees |
| `:Hangar kill <id>` | stop a running agent |
| `:Hangar clean` | delete worktrees/branches of all finished runs |
| `:checkhealth hangar` | diagnose setup problems (git, agent CLIs, repo state) |

Dashboard keys: `<CR>` transcript · `d` review/diff · `m` merge · `x` discard · `K` kill · `s` spawn · `r` refresh · `q` quit.

With `--n`, the dashboard groups the attempts under one shared prompt line; compare their diffs with `d`, and merging one offers to discard its siblings.

Every spawn needs an explicit `--yolo` or `--safe` — headless agents can't answer permission prompts, so you choose the blast radius per run. If you always want one mode:

```lua
opts = { default_permission = "yolo" }
```

## Configuration

```lua
require("hangar").setup({
  default_permission = nil,  -- "yolo" | "safe" | nil (require an explicit flag per spawn)
  merge = "squash",          -- "squash" | "ff" | "merge"
  adapter = "claude_code",   -- default agent CLI for spawns without --adapter
  model = nil,               -- default model for claude_code spawns, e.g. "haiku"
  adapters = {               -- per-adapter overrides (all optional)
    -- codex = { cmd = "/path/to/codex", model = "gpt-5.3-codex" },
  },
  notify = true,             -- notify when a run finishes and the dashboard is closed
                             -- (true | false | function(run) for a custom sink)
  max_concurrent = nil,      -- cap on simultaneously running agents; extra spawns
                             -- queue (◌) and start as slots free up. nil = unlimited
})
```

Lua API: `require("hangar").spawn(prompt, { permission_mode = "bypassPermissions", model = "haiku", adapter = "codex" })`.

### Statusline

`require("hangar").status()` returns `"hangar 2 ● 1 ✓"` (running / awaiting review / `✗` failed), or `""` when idle — cached, so it's safe on every redraw. lualine:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      function()
        -- guard keeps lazy.nvim from loading hangar just to render ""
        if not package.loaded["hangar"] then
          return ""
        end
        return require("hangar").status()
      end,
      "encoding",
      "filetype",
    },
  },
})
```

`require("hangar").status_counts()` returns the raw `{ running, queued, done, failed }` table for custom formatting.

### Pickers (optional)

Fuzzy-find runs by prompt, status, or id as an alternative to the dashboard — `<CR>` transcript, `<C-d>` review/diff, `<C-e>` iterate with feedback, `<C-x>` discard. The core plugin stays dependency-free; these load only if the host picker is installed.

```vim
" telescope.nvim:  :lua require('telescope').load_extension('hangar')  then
:Telescope hangar runs

" fzf-lua:
:lua require("hangar.pickers.fzf").runs()
```

## How it works

`:Hangar spawn` creates a worktree on branch `hangar/<id>` under `stdpath("cache")/hangar/worktrees/` — outside your repo, so agents can never touch your working tree — then runs `claude -p <prompt> --output-format stream-json` there via `vim.system`. Events stream into the run registry and every open UI updates through a `User HangarRunUpdate` autocmd. When a run finishes with uncommitted changes, hangar commits them so the branch is always mergeable. State persists to `stdpath("data")/hangar/runs.json`, so finished runs survive restarting Neovim. Runs that were live when you quit come back as **detached** (◎) while their agent process survives, then flip to **orphaned** (?) when it exits — and `R` in the dashboard resumes an orphaned run's session in its original worktree (claude and codex).

Adapters are a small contract (`name`, `build_cmd`, `parse_line`) — see `lua/hangar/adapters/`. Shipped adapters: **Claude Code** (`claude_code`, the default), **OpenAI Codex** (`codex`, via `codex exec --json`), **Gemini CLI** (`gemini`, via `gemini -p -o stream-json`), and **OpenCode** (`opencode`, via `opencode run --format json`).

`--yolo` / `--safe` map onto each CLI's own permission system:

| adapter | `--yolo` | `--safe` | safe mode verified |
| --- | --- | --- | --- |
| `claude_code` | `--permission-mode bypassPermissions` | `--permission-mode acceptEdits` (edits only) | ✅ live e2e |
| `codex` | `--dangerously-bypass-approvals-and-sandbox` | `--sandbox workspace-write` — weaker than claude's: sandboxed shell still allowed | ✅ live e2e |
| `gemini` | `--approval-mode yolo` | `--approval-mode auto_edit` | mapped per CLI docs, not live-verified |
| `opencode` | `--auto` | **unsupported** — spawn fails fast (headless opencode would hang on permission prompts) | ✅ fails fast |

## Tests

```sh
# parser + arg handling (offline, free)
nvim --headless -l tests/run_tests.lua

# full end-to-end with real agent runs (costs a few cents; adapters optional)
XDG_DATA_HOME=$(mktemp -d) nvim --headless -l tests/run_tests.lua --integration
XDG_DATA_HOME=$(mktemp -d) nvim --headless -l tests/run_tests.lua --integration codex
```

`--integration gemini` additionally needs working Gemini CLI auth.

## Contributing

New adapters are the most useful contribution: implement the three-field contract in `lua/hangar/adapters/` (capture real CLI output first and write the parser against it), add canned-line tests to `tests/run_tests.lua`, and verify a real run end-to-end with `--integration <name>`. The offline suite must pass for any change.

## License

MIT
