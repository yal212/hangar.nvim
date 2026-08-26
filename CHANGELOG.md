# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While 0.x, `setup()` option
names and the adapter contract are stable within a minor version; breaking changes bump the minor.

## [Unreleased]

### Fixed

- Reviewing a run that was still queued crashed on its missing base commit. `d` in the
  dashboard and `<C-d>`/`ctrl-d` in the pickers now report that the run has not started
  yet, and the dashboard stays open.
- `:Hangar kill <Tab>` completed only running runs, though `kill` also stops queued and
  detached ones. It now offers all three, filters on what you have typed, and returns a
  stable, sorted list.
- `:checkhealth hangar` probed each agent CLI's `--version` twice per adapter, doubling the
  worst-case wait. The version-probe timeout also drops from 10s to 5s.
- The run registry is now written to a temporary file and renamed into place, so an
  interrupted or failed write can no longer truncate `runs.json` and lose in-flight runs'
  worktree and branch mappings.

## [0.1.0] - 2026-08-26

First tagged release. Everything below shipped between 2026-07-12 and 2026-08-26.

### Added

- `CONTRIBUTING.md` with a dev setup, test instructions, and an adapter-authoring guide.
- `SECURITY.md` with a threat model for `--yolo` runs, plus `CODE_OF_CONDUCT.md`.
- Issue forms (bug, feature, adapter request) and a pull-request template.
- `.editorconfig` matching `stylua.toml`.
- `M.version`, reported by `:checkhealth hangar`.
- `setup()` now validates its options: unknown keys, wrong types and out-of-range values are
  reported by name instead of being silently merged.
- `Makefile` with `check`, `test`, `test-one FILTER=...`, `fmt`, `lint`, `typecheck`, `docs`,
  `coverage` and `hooks` targets. CI runs the same targets, so local and CI results cannot drift.
- Optional pre-commit hook (`make hooks`) running `make lint`.
- A rockspec, so the plugin can be installed with luarocks/rocks.nvim.

### Deprecated

- `config.claude_cmd` now warns on use and will be removed in 0.3.0. Use
  `adapters = { claude_code = { cmd = ... } }` instead.

### Fixed

- The demo stub (`assets/demo/fake-claude`) ignored `--version` and ran its whole scenario instead,
  so `:checkhealth hangar` during a demo wrote the canned edits into the repo being demoed. It now
  answers and exits like the real CLI.
- The demo stub mishandled scenario files whose paths contain spaces.

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

- CI running the offline test suite and `stylua --check` on push and pull request, later extended
  with luacheck, `lua-language-server --check`, shellcheck, luacov coverage, and a Neovim version
  matrix (0.10, stable, nightly).
- Test suite split from one 912-line script into per-module specs under `tests/spec/`, with a
  shared harness and a `--filter` flag for running a subset.
- Docs drift guard (`scripts/check-docs.lua`, `make docs`): config keys, adapter names, `:Hangar`
  subcommands, the version and vimdoc help tags are asserted against the code on every PR.
- Release workflow: pushing a `vX.Y.Z` tag publishes a GitHub release from the matching CHANGELOG
  section, after checking the tag agrees with `M.version`.
- Internal split: `hangar.store` (registry persistence), `hangar.ui.render` and `hangar.ui.actions`
  extracted from `runner.lua` and `dashboard.lua`; shared `hangar.util` notification helpers.

[Unreleased]: https://github.com/yal212/hangar.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yal212/hangar.nvim/releases/tag/v0.1.0
