## What and why

<!-- What does this change, and what problem does it solve? Link the issue: Closes #123 -->

## Checklist

- [ ] `make check` is clean (lint, typecheck, offline test suite, docs check)
- [ ] `doc/hangar.txt` updated (if the change is user-facing) — `make docs` fails if the
      README and the vimdoc fall behind the code
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]` (if the change is user-facing)
- [ ] Commit subjects follow [conventional commits](https://www.conventionalcommits.org/)

## Adapter changes only

- [ ] Parser tested against real captured CLI output, with canned lines added to
      `tests/spec/<adapter>_spec.lua`
- [ ] Verified end-to-end with `make integration ADAPTERS="<adapter>"`
      (this spawns the real CLI and **costs money**)
- [ ] `--yolo` / `--safe` mapping added to the table in the README
