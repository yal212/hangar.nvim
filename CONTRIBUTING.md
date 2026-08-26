# Contributing to hangar.nvim

Thanks for taking a look. This file should get you from a clone to a passing test run to a new
adapter without reading the source first.

## Local development

Point Neovim at your checkout instead of the published plugin.

With lazy.nvim:

```lua
{
  dir = "~/src/hangar.nvim", -- your clone
  cmd = "Hangar",
  opts = {},
}
```

Or with a scratch config, which is the quickest way to test in isolation:

```lua
-- ~/hangar-dev.lua
vim.opt.runtimepath:prepend("~/src/hangar.nvim")
require("hangar").setup({})
```

```sh
nvim -u ~/hangar-dev.lua
```

`assets/demo/init.lua` is a working example of the same idea — it also shows how to point an
adapter at a stub executable (`adapters = { claude_code = { cmd = ... } }`), which is handy for
developing against fake CLI output.

hangar has no runtime dependencies. Neovim >= 0.10 is the floor (it uses `vim.system` and
`vim.uv`), and CI verifies 0.10, stable, and nightly.

## Tests

The suite is plain headless Lua — no plenary, no busted. `tests/run_tests.lua` discovers every
`tests/spec/*_spec.lua`, hands each a shared harness, and reports one `ok`/`FAIL` line per
assertion.

```sh
make test                       # offline: parsers, arg handling, worktree/git lifecycle. Free.
make test-one FILTER=codex      # just the specs whose filename matches
```

Layout:

| path | what lives there |
|---|---|
| `tests/run_tests.lua` | entry point: bootstrap, spec discovery, `--filter`, exit code |
| `tests/harness.lua` | `check()`, `sh()`, `git_repo()`, the stub adapters, per-spec config reset |
| `tests/spec/*_spec.lua` | one file per module; each returns `function(harness)` |
| `tests/integration/` | the real-CLI end-to-end runs |

Specs must be order-independent: the harness resets `hangar.config` between files and registers the
`fake` / `fakeresume` stub adapters up front, so `--filter` gives the same result as a full run.
Clean up anything you add to `runner.runs`.

> [!WARNING]
> **`--integration` costs money.** It spawns the real agent CLIs against a throwaway repo and
> burns API credits (a few cents per adapter, more if a run goes long). It is never run in CI and
> is not required for a PR unless you changed an adapter.

```sh
# end-to-end with real agent runs — spends money
make integration
make integration ADAPTERS="codex opencode"
```

Adapter names default to `claude_code`. Append `:safe` to run one with `acceptEdits`, e.g.
`claude_code:safe`. The `XDG_DATA_HOME` prefix keeps the run registry out of your real state dir.
`--integration gemini` additionally needs working Gemini CLI auth.

The offline suite must pass for every change.

## Formatting and lint

```sh
make check      # everything CI runs: lint, typecheck, test, docs
make fmt        # stylua, in place
make lint       # stylua --check (stylua.toml), luacheck (.luacheckrc), shellcheck
make typecheck  # lua-language-server, uses .luarc.json
make docs       # asserts the docs still match the code (see below)
make hooks      # optional: install a pre-commit hook that runs `make lint`
```

CI invokes these same targets, so a green `make check` locally means a green CI.
`.editorconfig` carries the same conventions for non-Lua files.

### The docs check

`make docs` runs `scripts/check-docs.lua`, which fails the build when the code and the docs
disagree: every `setup()` option must appear in both `README.md` and `doc/hangar.txt`, every shipped
adapter and `:Hangar` subcommand must be documented, `M.version` must match the newest dated
`CHANGELOG.md` heading, and every `|hangar-xxx|` cross-reference must resolve to a real tag. It
deliberately checks only these mechanical facts — prose is never checked.

## Commits and PRs

- Commit subjects follow [conventional commits](https://www.conventionalcommits.org/) —
  `feat(runner): ...`, `fix(ui): ...`, `docs: ...`, `ci: ...`. The whole history is consistent;
  `CHANGELOG.md` is grouped from it.
- Add an entry under `## [Unreleased]` in `CHANGELOG.md` for anything user-facing.
- Update `doc/hangar.txt` alongside user-facing changes — the README and the vimdoc are expected
  to agree.
- The PR template's checklist is the whole review bar; run it before pushing.

## Adding an adapter

New adapters are the most useful contribution. An adapter is one file in `lua/hangar/adapters/`
that returns a table with three required fields:

| field | type | |
|---|---|---|
| `name` | `string` | must match the file name (`opencode.lua` → `"opencode"`) |
| `build_cmd(opts)` | `fun(opts: hangar.SpawnCmdOpts): string[]` | the argv to spawn |
| `parse_line(line)` | `fun(line: string): table\|nil` | one line of CLI output → one normalized event |

Optional:

| field | type | |
|---|---|---|
| `unsupported_modes` | `table<string, string>` | permission mode → reason; spawn fails fast instead of hanging |
| `build_resume_cmd(opts)` | `fun(opts: hangar.ResumeCmdOpts): string[]` | resume an orphaned run's session |

`hangar.SpawnCmdOpts` and `hangar.ResumeCmdOpts` are declared in `lua/hangar/adapters/init.lua`,
which owns the contract. `opts` for `build_cmd` is `hangar.SpawnCmdOpts`: `prompt`, `permission_mode`
(`"bypassPermissions"` for `--yolo`, `"acceptEdits"` for `--safe`), `model`, `cmd` (the user's
executable override), and `cwd` (the worktree path — pass it as a flag if the CLI doesn't honour
the spawn cwd; `opencode` needs `--dir`).

`parse_line` returns `nil` for anything it doesn't recognise (unknown event types are ignored on
purpose — CLIs add them over time) or one event:

| `kind` | fields | meaning |
|---|---|---|
| `init` | `session_id`, `model` | run started; `session_id` enables resume |
| `text` | `text`, `delta` | assistant prose. Set `delta = true` if the CLI streams fragments — the runner coalesces them |
| `tool_use` | `tool`, `summary` | a tool call. `util.input_summary(input)` builds the summary |
| `tool_result` | `text`, `is_error` | its result. `util.truncate(s, 120)` keeps it one line |
| `batch` | `events` | several of the above from one line, applied in order |
| `result` | `cost`, `turns`, `is_error`, `text`, `partial` | final stats. `partial = true` accumulates instead of replacing (per-step costs) |

### Steps

1. **Capture real output first.** Run the CLI headlessly, redirect to a file, and write the parser
   against those exact lines. Guessing the schema from docs does not work.
2. Copy `lua/hangar/adapters/opencode.lua` (85 lines, the smallest) as your skeleton.
3. Map `--yolo` / `--safe` onto the CLI's own approval flags. If it has **no** non-interactive safe
   mode, declare `unsupported_modes = { acceptEdits = "<reason>" }` — a headless run that waits on
   a permission prompt hangs forever, so failing fast is the correct behaviour.
4. Add `tests/spec/<name>_spec.lua` modelled on `tests/spec/opencode_spec.lua` — one assertion per
   event kind, using your captured lines verbatim, plus the blank/garbage-line cases.
5. Document the adapter in `README.md` and `doc/hangar.txt`; `make docs` fails until you do.
6. Verify a real run: `make integration ADAPTERS="<name>"`.
6. Add a row to the permission table in the README and mention the adapter in `doc/hangar.txt`.

The registry (`lua/hangar/adapters/init.lua`) discovers adapters from the runtimepath and validates
the contract, so there is nothing to register by hand.

## The demo GIF

`assets/demo.gif` is scripted — `vhs assets/demo.tape` re-records it from the repo root. It drives
the real plugin against a throwaway fixture repo, with `assets/demo/fake-claude` standing in for
the agent CLI, so re-recording is deterministic and costs nothing.
