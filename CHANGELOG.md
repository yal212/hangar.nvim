# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While 0.x, `setup()` option
names and the adapter contract are stable within a minor version; breaking changes bump the minor.

## [Unreleased]

### Changed

- `setup()` now ignores the options it reports as invalid, so they keep their previous
  values. Before, it reported a bad value and then applied it anyway. `max_concurrent`
  must also be a whole number >= 1: `0` used to be accepted silently, and then every
  spawn queued forever.

### Fixed

- `:Hangar clean` run before anything else had loaded the run registry (a fresh Neovim
  session with the dashboard never opened) saved an empty registry, wiping the records of
  every repo's runs and leaking their worktrees and branches. `:Hangar kill <id>` typed
  without `<Tab>` completion likewise answered "no such run". Every run operation now loads
  the persisted registry first.
- Merging a failed, killed or orphaned run lost its work. Only runs that finish "done" are
  auto-committed, so these runs' edits sat uncommitted in the worktree. Review showed them,
  but the merge took the empty branch: with `merge = "ff"` or `"merge"` it reported success
  and then deleted the worktree, edits and all. With `"squash"` it failed with a blank
  "commit after squash failed:" error. Leftover edits are now committed to the run's branch
  before merging.
- Merging a run that changed nothing is now refused with "run has no changes to merge",
  instead of failing obscurely (squash) or deleting the worktree (ff/merge).
- An untracked file anywhere in your working tree blocked every merge as "dirty". Only
  tracked changes count now; git still refuses a merge that would overwrite an untracked
  file.
- Spawning with an agent CLI that is not installed raised a Lua error and left the run stuck
  as "running" with no process behind it: `K` said it was not running, `x` said it was
  still running, it held a `max_concurrent` slot for the rest of the session, and its
  worktree leaked. The spawn now fails with "could not start <cli>" and leaves nothing
  behind; a queued run that hits this when its turn comes is marked failed, and a failed
  resume or iterate leaves the original run as it was.
- The last line of an agent's output stream was dropped when it had no trailing newline.
  That line is usually the final result, so the run lost its cost and turn count, and a
  failed result could even be recorded as "done".
- With `max_concurrent` set, runs queued within the same second (a `--n` fleet, or quick
  successive spawns) left the queue in arbitrary order rather than oldest-first.
- Discarding a run while its transcript was open raised an error from the transcript's
  update handler. The transcript now keeps what it showed and adds a note that the run was
  discarded.
- Long prompts and tool output were cut at a byte count, which could split a multibyte
  character (CJK text, emoji, accented letters) and show `<e4><bf>`-style garbage in the
  dashboard, the pickers, transcript tool lines and notifications, or put invalid UTF-8 in
  auto-commit messages. Text is now cut only between characters.
- The dashboard was sized one line short of its content, so with two or more runs the
  key-hint line was hidden (more with best-of-n group headers), and it never grew as runs
  were added. It now fits its content and resizes as rows come and go.
- When rows moved under the cursor (a new run spawned, or a `status`/`cost` sort reordered
  them as runs finished), the dashboard cursor stayed on the same line and so landed on a
  different run, where `K` would kill it without asking. The cursor now stays on its run.
- Spawning past `max_concurrent` announced "spawned run X on branch nil". It now says the
  run is queued and will start when a slot frees up.
- Best-of-n group ids came from the clock time alone, so a fleet started at the same time
  of day as an older one still in the registry joined its group. The dashboard merged the
  two, and merging one run offered to discard the other fleet's attempts. Iteration
  lineages had the same problem once a run id was reused. Group ids are now unique in the
  registry.
- Rebase-and-retry no longer rebases the branch of a run that is still running, and merging
  a run whose branch an iteration took over now says so instead of failing inside git.

## [0.2.0] - 2026-08-26

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
- Opening the transcript of an iterated run failed with an error instead of showing the
  transcript: the feedback appended by `i` makes the prompt multi-line, and the prompt is
  rendered as a single header line. It is now collapsed, as the dashboard and the pickers
  already did.

### Infrastructure

- Test coverage for the previously untested UI layer: the transcript renderer, the review
  float, dashboard row building, highlight groups, status icons and the telescope picker.
  Every module under `lua/` now has at least one spec.
- `setup()` options and the adapter contract now carry real LuaLS annotations, so an
  LSP-enabled editor completes every option and type-checks the table you pass. Two
  supporting fixes make that work rather than decorative: `.luarc.json` gained a
  `runtime.path`, without which `require("hangar")` resolved to `any` and nothing was
  checked across module boundaries; and the docs guard now fails when an option gains a
  `SCHEMA` entry without a matching `---@field`.

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

[Unreleased]: https://github.com/yal212/hangar.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/yal212/hangar.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yal212/hangar.nvim/releases/tag/v0.1.0
