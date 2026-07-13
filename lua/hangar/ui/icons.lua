---Single source of truth for run-status icons and their highlight groups
---(consumed by the dashboard, the pickers, and the statusline).
local M = {}

---@type table<string, { icon: string, hl: string }>
M.STATUS = {
  queued = { icon = "◌", hl = "HangarQueued" },
  running = { icon = "●", hl = "HangarRunning" },
  done = { icon = "✓", hl = "HangarDone" },
  failed = { icon = "✗", hl = "HangarFailed" },
  killed = { icon = "⊘", hl = "HangarFailed" },
  merged = { icon = "⇡", hl = "HangarMerged" },
  orphaned = { icon = "?", hl = "HangarOrphaned" },
  detached = { icon = "◎", hl = "HangarDetached" },
}

---@param status string
---@return { icon: string, hl: string }
function M.get(status)
  return M.STATUS[status] or { icon = " ", hl = "HangarDim" }
end

return M
