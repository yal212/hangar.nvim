---Shared highlight groups (default links; users can override).
local M = {}

---Define hangar's highlight groups as default links. Idempotent, and called
---on every dashboard/transcript/review open — `default = true` means a
---colorscheme or user override always wins.
function M.define()
  local links = {
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
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

return M
