# hangar.nvim demo recording.
#
#   vhs assets/demo.tape      # from the repo root
#
# Everything on screen is the real plugin: real git worktrees, real streaming
# stream-json through the real adapter, real diffsplit, real squash merge. Only
# the agent is scripted — assets/demo/fake-claude stands in for `claude`, so the
# recording is deterministic, free, and reproducible without an API key.
#
# The `4G` motions jump to the dashboard's first run row (line 1 is blank,
# line 2 the column header, line 3 the fleet's shared prompt line).

Output assets/demo.gif

Set Shell "bash"
Set FontSize 16
Set Width 1240
Set Height 700
Set Padding 20
Set Framerate 20
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

# --- setup: throwaway fixture repo + empty hangar state, then launch nvim -----
Hide
Type "source assets/demo/seed-repo.sh && clear"
Enter
Sleep 2s
# open a file so the recording starts on real work, not an empty buffer
Type "nvim -u $HANGAR_DEMO_ROOT/assets/demo/init.lua src/settings.js"
Enter
Sleep 3s
Show

Sleep 800ms

# --- spawn a single run ------------------------------------------------------
Type ":Hangar spawn --yolo fix the flaky auth test"
Sleep 500ms
Enter
Sleep 1200ms

# --- spawn a best-of-3 fleet on a second task --------------------------------
Type ":Hangar spawn --n 3 --yolo add dark mode to the settings page"
Sleep 500ms
Enter
Sleep 1s

# --- mission control ---------------------------------------------------------
Type ":Hangar"
Enter
Sleep 1800ms

# --- tail one attempt's transcript while it works ----------------------------
Type "4G"
Sleep 400ms
Enter
Sleep 4s
Type "q"
Sleep 500ms

# --- review that attempt's diff against its base commit ----------------------
Type ":Hangar"
Enter
Sleep 1200ms
Type "4G"
Sleep 400ms
Type "d"
Sleep 1500ms
Enter
Sleep 3s
Type "q"
Sleep 500ms

# --- merge the winner, discard its siblings ----------------------------------
Type ":Hangar"
Enter
Sleep 1200ms
Type "4G"
Sleep 400ms
Type "m"
Sleep 1200ms
Type "y"
Sleep 1400ms
Type "y"
Sleep 3s
