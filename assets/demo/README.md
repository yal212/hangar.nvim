# Demo recording

`vhs assets/demo.tape` (run from the repo root) re-records `assets/demo.gif`.

Everything in the recording is the real plugin — real git worktrees, real
streaming `stream-json` through the real `claude_code` adapter, real
`diffsplit`, real squash merge. Only the agent is scripted, so the take is
deterministic, free, and reproducible without an API key.

| file | what it is |
| --- | --- |
| `../demo.tape` | the vhs script: window size, timings, every keystroke |
| `seed-repo.sh` | sourced by the tape; builds the throwaway fixture repo and points `XDG_{DATA,CACHE,STATE}_HOME` at fresh temp dirs so each take starts from zero state |
| `init.lua` | minimal Neovim config; its only hangar setting is the `adapters.claude_code.cmd` override |
| `fake-claude` | stub agent CLI — same argv and same `stream-json` protocol as `claude`, with canned events on a fixed timeline |
| `fixture/` | contents of the demo repo (`fleetdash`, a toy settings panel) |
| `scenes/<name>/` | files a scenario writes into its worktree, one `Edit` tool call each |

Scenario picking lives in `fake-claude`: the auth prompt gets `scenes/auth`,
and the dark-mode prompt claims the next unused `scenes/darkmode-N` (an atomic
`mkdir`), so the three attempts of the `--n 3` fleet produce different diffs and
finish at different times.

Requires [vhs](https://github.com/charmbracelet/vhs) (`brew install vhs`).

The `4G` motions in the tape jump to the dashboard's first run row — line 1 is
blank, line 2 the column header, line 3 the fleet's shared prompt line. Adjust
them if the dashboard's header layout changes.
