---`:checkhealth hangar` — self-diagnose setup problems.
local M = {}

local health = vim.health

local function version_of(exe)
  local ok, res = pcall(function()
    return vim.system({ exe, "--version" }, { text = true }):wait(5000)
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  return vim.split(vim.trim(res.stdout or ""), "\n")[1]
end

function M.check()
  health.start("hangar.nvim")

  health.ok(("hangar.nvim %s"):format(require("hangar").version))

  -- Neovim version (vim.system, autocmd data)
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim >= 0.10 required (hangar uses vim.system)", "Upgrade Neovim.")
  end

  -- git with worktree support
  if vim.fn.executable("git") == 1 then
    local v = version_of("git") or ""
    local major, minor = v:match("(%d+)%.(%d+)")
    if major and (tonumber(major) > 2 or (tonumber(major) == 2 and tonumber(minor) >= 5)) then
      health.ok(("git found: %s"):format(v))
    else
      health.error(("git %s is too old for `git worktree`"):format(v), "Install git >= 2.5.")
    end
  else
    health.error("git not found on PATH", "Install git — hangar cannot create worktrees without it.")
  end

  -- agent CLIs, configured default first
  local config = require("hangar").config
  local registry = require("hangar.adapters")
  for _, name in ipairs(registry.available()) do
    local adapter = registry.get(name)
    if adapter then
      local overrides = config.adapters[name] or {}
      local exe = overrides.cmd
        or (name == "claude_code" and config.claude_cmd ~= "claude" and config.claude_cmd)
        or adapter.build_cmd({ prompt = "", permission_mode = "acceptEdits" })[1]
      local is_default = name == config.adapter
      local label = is_default and (name .. " (default adapter)") or name
      if vim.fn.executable(exe) == 1 then
        -- one probe per adapter: version_of spawns a process, so calling it twice
        -- (once to test, once for the value) doubled :checkhealth's worst-case wait
        local ver = version_of(exe)
        health.ok(("%s: `%s` found%s"):format(label, exe, ver and (" — " .. ver) or ""))
      elseif is_default then
        health.error(
          ("%s: `%s` not found on PATH"):format(label, exe),
          ("Install it or point setup({ adapters = { %s = { cmd = ... } } }) at the executable."):format(name)
        )
      else
        health.warn(("%s: `%s` not found on PATH (only needed for --adapter %s runs)"):format(label, exe, name))
      end
    end
  end

  -- current directory usable as a base
  local root = require("hangar.worktree").root()
  if not root then
    health.warn(
      "current directory is not a git repository",
      ":Hangar only works inside a git repo — cd into one before spawning."
    )
  else
    local res = vim.system({ "git", "rev-parse", "HEAD" }, { cwd = root, text = true }):wait()
    if res.code == 0 then
      health.ok(("git repo detected: %s"):format(root))
    else
      health.error(
        "git repo has no commits yet",
        "hangar branches worktrees off HEAD — make an initial commit first."
      )
    end
  end

  -- persisted state
  local state = require("hangar.store").path()
  local f = io.open(state, "r")
  if not f then
    health.ok("no state file yet (created on first spawn): " .. state)
  else
    local content = f:read("*a")
    f:close()
    local ok, decoded = pcall(vim.json.decode, content)
    if ok and type(decoded) == "table" then
      health.ok(("state file OK (%d run(s)): %s"):format(vim.tbl_count(decoded), state))
    else
      health.error(
        "state file is corrupt: " .. state,
        "Delete it to start fresh — finished-run history will be lost, worktrees are untouched."
      )
    end
  end
end

return M
