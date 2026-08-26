---Shared highlight groups and status icons: the two tables the dashboard,
---transcript, review float and pickers all render through.
---@param harness table
return function(harness)
  local check = harness.check
  local hl = require("hangar.ui.hl")
  local icons = require("hangar.ui.icons")

  -- Every group ui/hl.lua promises, linked to the target it promises.
  local EXPECTED_LINKS = {
    HangarQueued = "Comment",
    HangarRunning = "DiagnosticInfo",
    HangarDone = "DiagnosticOk",
    HangarFailed = "DiagnosticError",
    HangarMerged = "Special",
    HangarOrphaned = "DiagnosticWarn",
    HangarDetached = "DiagnosticHint",
    HangarDim = "Comment",
    HangarHeader = "Title",
    HangarToolUse = "Function",
  }

  hl.define()
  for group, link in pairs(EXPECTED_LINKS) do
    local got = vim.api.nvim_get_hl(0, { name = group })
    check(got.link == link, ("hl: %s links to %s"):format(group, link))
    check(got.default == true, ("hl: %s is a default link, so a colorscheme can override it"):format(group))
  end

  -- define() is called on every dashboard/transcript/review open, so a user's
  -- own `HangarRunning` must survive being re-defined — that is the whole point
  -- of `default = true` in nvim_set_hl.
  vim.api.nvim_set_hl(0, "HangarRunning", { link = "ErrorMsg" })
  hl.define()
  check(
    vim.api.nvim_get_hl(0, { name = "HangarRunning" }).link == "ErrorMsg",
    "hl: define() does not clobber a user override"
  )
  vim.api.nvim_set_hl(0, "HangarRunning", {}) -- leave the group as we found it
  hl.define()

  -- icons: one entry per status the runner and store can assign
  local EXPECTED_ICONS = {
    queued = { icon = "◌", hl = "HangarQueued" },
    running = { icon = "●", hl = "HangarRunning" },
    done = { icon = "✓", hl = "HangarDone" },
    failed = { icon = "✗", hl = "HangarFailed" },
    killed = { icon = "⊘", hl = "HangarFailed" },
    merged = { icon = "⇡", hl = "HangarMerged" },
    orphaned = { icon = "?", hl = "HangarOrphaned" },
    detached = { icon = "◎", hl = "HangarDetached" },
  }
  for status, want in pairs(EXPECTED_ICONS) do
    local got = icons.get(status)
    check(got.icon == want.icon and got.hl == want.hl, ("icons: %s renders %s/%s"):format(status, want.icon, want.hl))
  end
  check(
    vim.tbl_count(icons.STATUS) == vim.tbl_count(EXPECTED_ICONS),
    "icons: STATUS has no status this spec does not know about"
  )

  local fallback = icons.get("no-such-status")
  check(fallback.icon == " " and fallback.hl == "HangarDim", "icons: unknown status falls back to a blank icon")

  -- Cross-module contract: every group icons.STATUS names must be one that
  -- hl.define() actually creates, or the dashboard's status column renders
  -- against an undefined highlight.
  for status, entry in pairs(icons.STATUS) do
    check(EXPECTED_LINKS[entry.hl] ~= nil, ("icons: %s uses a group hl.define() creates (%s)"):format(status, entry.hl))
  end
  check(EXPECTED_LINKS[fallback.hl] ~= nil, "icons: the fallback group is one hl.define() creates")
end
