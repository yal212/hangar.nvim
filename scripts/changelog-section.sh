#!/usr/bin/env bash
# Print one version's section of CHANGELOG.md, for use as GitHub release notes.
#
#   scripts/changelog-section.sh 0.1.0
#
# Exits non-zero if that version has no section, so a release never publishes
# with empty or wrong notes.
set -euo pipefail

version="${1:?usage: changelog-section.sh <X.Y.Z>}"
changelog="$(dirname "$0")/../CHANGELOG.md"

section="$(awk -v want="## [$version]" '
  index($0, want) == 1 { found = 1; next }
  found && /^## \[/    { exit }
  found                { print }
' "$changelog")"

# strip leading and trailing blank lines
section="$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$section" ]; then
  echo "no CHANGELOG.md section for version $version" >&2
  exit 1
fi

printf '%s\n' "$section"
