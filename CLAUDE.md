# CLAUDE.md

Project rules for AI assistants working in this repo. Everything in `CONTRIBUTING.md` applies too —
this file only covers what is specific to automated contributors.

## Attribution

Agent-authored work is credited by a `Co-Authored-By:` trailer and nothing else.

- **Never** append a `Claude-Session:` trailer — or any `https://claude.ai/code/session_…` URL — to
  a commit message. Those links resolve only inside one person's local Claude Code install, so they
  are noise in a public history. `scripts/hooks/commit-msg` strips them, but do not rely on the
  hook: do not write them in the first place.
- **Never** append a `🤖 Generated with [Claude Code]` footer, or a session URL, to a PR body, an
  issue, a comment, or a review. No hook can catch these — this rule is the only guard.
- `Co-Authored-By: Claude <model> <noreply@anthropic.com>` is welcome and stays.

The history was rewritten once to remove these trailers. Do not reintroduce them.

## Everything else

Read `CONTRIBUTING.md`: conventional-commit subjects, `make check` before pushing, a `CHANGELOG.md`
entry under `[Unreleased]` for user-facing changes, and `doc/hangar.txt` kept in step with the
README.
