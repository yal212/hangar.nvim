#!/usr/bin/env bash
# Build the throwaway fixture repo the demo recording runs against, and point
# every bit of hangar state at fresh temp dirs so each take starts from zero.
#
# Source it (don't execute it) — it cds into the fixture repo:
#   source assets/demo/seed-repo.sh

HANGAR_DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HANGAR_DEMO_ROOT

# Fresh XDG dirs: runs.json lives under stdpath("data")/hangar and the worktrees
# under stdpath("cache")/hangar, so this is what makes the recording repeatable.
HANGAR_DEMO_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hangar-demo.XXXXXX")"
export HANGAR_DEMO_TMP
export XDG_DATA_HOME="$HANGAR_DEMO_TMP/data"
export XDG_CACHE_HOME="$HANGAR_DEMO_TMP/cache"
export XDG_STATE_HOME="$HANGAR_DEMO_TMP/state"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"

repo="$HANGAR_DEMO_TMP/fleetdash"
mkdir -p "$repo"
cp -R "$HANGAR_DEMO_ROOT/assets/demo/fixture/." "$repo/"

git -C "$repo" init -q -b main
git -C "$repo" config user.name "Fleet Dash"
git -C "$repo" config user.email "demo@example.com"
git -C "$repo" config commit.gpgsign false
git -C "$repo" add -A
git -C "$repo" commit -qm "initial settings panel"

cd "$repo" || return 1
