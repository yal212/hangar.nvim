## What and why

<!-- What does this change, and what problem does it solve? Link the issue: Closes #123 -->

## Checklist

- [ ] Offline test suite passes: `nvim --headless -l tests/run_tests.lua`
- [ ] `stylua --check lua/ plugin/ tests/` is clean
- [ ] `luacheck lua plugin tests` is clean
- [ ] `doc/hangar.txt` updated (if the change is user-facing)
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]` (if the change is user-facing)
- [ ] Commit subjects follow [conventional commits](https://www.conventionalcommits.org/)

## Adapter changes only

- [ ] Parser tested against real captured CLI output, with canned lines added to the test suite
- [ ] Verified end-to-end with `nvim --headless -l tests/run_tests.lua --integration <adapter>`
      (this spawns the real CLI and **costs money**)
- [ ] `--yolo` / `--safe` mapping added to the table in the README
