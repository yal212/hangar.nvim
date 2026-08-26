#!/usr/bin/env bash
# Assert a release tag agrees with the version the code and CHANGELOG claim.
#
#   scripts/check-version.sh v0.1.0
#
# Run before publishing, so a mistyped tag fails loudly instead of shipping a
# release whose notes and :checkhealth version disagree with each other.
set -euo pipefail

tag="${1:?usage: check-version.sh <vX.Y.Z>}"
version="${tag#v}"
root="$(cd "$(dirname "$0")/.." && pwd)"
status=0

code_version="$(sed -n 's/^M\.version = "\(.*\)"$/\1/p' "$root/lua/hangar/init.lua")"
if [ -z "$code_version" ]; then
  echo "could not read M.version from lua/hangar/init.lua" >&2
  exit 1
fi

if [ "$code_version" != "$version" ]; then
  echo "tag $tag disagrees with M.version ($code_version) in lua/hangar/init.lua" >&2
  status=1
fi

if ! grep -qE "^## \[${version}\] - [0-9]" "$root/CHANGELOG.md"; then
  echo "CHANGELOG.md has no dated '## [$version] - <date>' heading" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "version OK: $tag matches M.version and CHANGELOG.md"
fi
exit "$status"
