# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While 0.x, `setup()` option
names and the adapter contract are stable within a minor version; breaking changes bump the minor.

## [Unreleased]

### Added

- `CONTRIBUTING.md` with a dev setup, test instructions, and an adapter-authoring guide.
- `SECURITY.md` with a threat model for `--yolo` runs, plus `CODE_OF_CONDUCT.md`.
- Issue forms (bug, feature, adapter request) and a pull-request template.
- `.editorconfig` matching `stylua.toml`.
- `M.version`, reported by `:checkhealth hangar`.

## [0.1.0] - 2026-08-23

First tagged release. Everything below shipped between 2026-07-12 and 2026-08-23.

### Added

- **Core**: worktree lifecycle, run registry persisted to `stdpath("data")/hangar/runs.json`, and
  the Claude Code `stream-json` adapter. `:Hangar spawn` runs an agent in a git worktree on branch
  `hangar/<id>`.
- **Adapters**: a registry with the `--adapter` flag and four shipped adapters — `claude_code`
  (default), `codex` (`codex exec --json`), `gemini` (`gemini -p -o stream-json`), and `opencode`
  (`opencode run --format json`).
- **Dashboard**: live float listing runs with actions, updated through a `User HangarRunUpdate`
  autocmd; later gained an adapter column, a totals footer, and sorting and filtering.
- **Transcript**: streaming tail of the agent's events with live updates.
- **Review**: float with per-file diffsplit and merge/discard actions.
- **Fleet spawn**: `--n <count>` runs the same prompt in parallel worktrees, grouped in the
  dashboard.
- **Concurrency cap**: `max_concurrent` parks extra spawns as `queued` and starts them as slots
  free.
- **Detached runs**: runs live at quit come back as detached and flip to orphaned when their
  process exits; `R` resumes an orphaned run's session in its original worktree (claude, codex).
- **Iterate**: send follow-up feedback to a finished run instead of starting over.
- **Merge conflicts**: detected on merge, with a rebase-and-retry flow instead of an error.
- **Pickers**: telescope extension and fzf-lua picker for runs.
- **Statusline**: `require("hangar").status()` component for lualine and friends.
- **`:checkhealth hangar`**: Neovim version, git, per-adapter executables, repo state, and the
  run registry.
- **Notifications**: notify on run completion when the dashboard is closed; configurable via
  `notify`.
- **Docs**: README, `doc/hangar.txt`, MIT license, and a scripted demo GIF (`vhs assets/demo.tape`).

### Changed

- Merging a run with conflicts now offers rebase-and-retry rather than failing outright.

### Fixed

- Worktrees are created outside the repository, so an agent cannot escape into the user's working
  tree.
- Spawns fail fast when an adapter has no headless safe mode (`opencode` with `--safe`), instead of
  hanging on a permission prompt the run can never answer.
- Statusline spacing between count and icon.

### Infrastructure

- CI running the offline test suite and `stylua --check` on push and pull request.

[Unreleased]: https://github.com/yal212/hangar.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yal212/hangar.nvim/releases/tag/v0.1.0
