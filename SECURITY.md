# Security Policy

## Supported versions

hangar.nvim is pre-1.0. Only the latest release line receives fixes.

| Version | Supported |
| --- | --- |
| 0.1.x | ✅ |
| `main` | ✅ (best effort) |
| older | ❌ |

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's [private vulnerability reporting](https://github.com/yal212/hangar.nvim/security/advisories/new)
on this repository. If that's unavailable, email <yal212yal@gmail.com> with `hangar.nvim security`
in the subject.

Include the Neovim version, the adapter involved, and a reproduction if you have one. Expect an
acknowledgement within a week. This is a small volunteer project — there is no bounty.

## Threat model

hangar.nvim exists to run coding agents **with their permission prompts disabled**:
`:Hangar spawn --yolo` maps to `bypassPermissions` (or each adapter's equivalent). You are handing
an LLM unattended write and shell access. That is the point of the tool, and it is worth being
precise about what is and isn't contained.

### What hangar guarantees

**Runs cannot touch your working tree.** Every spawn creates a git worktree on branch
`hangar/<id>` under `stdpath("cache")/hangar/worktrees/` — deliberately outside your repository,
not in a `.git/` subdirectory of it. The agent's working directory is that worktree. Your checkout,
your uncommitted changes, and your branch are untouched until you explicitly merge from the review
UI. There is a regression test for worktree escape in `tests/run_tests.lua`, and adapters that
resolve their project directory independently (`opencode`) are pinned to the worktree explicitly.

Nothing is merged without your action: a finished run leaves a branch, and merging is a keypress in
the dashboard.

### What hangar does *not* guarantee

- **No filesystem sandbox.** The worktree is where the agent is *told* to work and where its cwd
  is set; it is not a jail. An agent that writes to an absolute path outside the worktree, or runs
  `rm -rf ~`, is limited only by whatever sandboxing the agent CLI itself provides — which under
  `--yolo` is generally none. See the per-adapter permission table in the
  [README](README.md#how-it-works): `codex --sandbox workspace-write` is the only shipped safe mode
  that restricts shell commands at all.
- **No network isolation.** The agent has full network access and can reach anything your
  credentials reach — your cloud accounts, your package registries, your internal services.
- **No secret redaction.** Prompts, file contents, and tool output go to the agent CLI's provider.
  The run registry (`stdpath("data")/hangar/runs.json`) and transcripts are stored unencrypted with
  default permissions; anything the agent printed is in there.
- **`--yolo` means no confirmation, ever.** Destructive shell commands are not previewed and not
  approved. `--safe` (`acceptEdits`) is weaker than it sounds — it removes the prompt for *edits*;
  what else it allows is per-CLI, and `opencode` has no headless safe mode at all (hangar refuses
  the spawn rather than hanging).
- **Prompt injection is unmitigated.** Content the agent reads — a file, a fetched page, a
  dependency's README — can steer it. Untrusted repository content plus `--yolo` is an unsafe
  combination, and hangar does nothing to detect it.

### Recommendations

- Prefer `--safe` for repositories or prompts you don't fully trust.
- Treat a `--yolo` run the way you'd treat running a script you didn't read.
- Review the diff in the review float before merging. That step exists for this reason.
