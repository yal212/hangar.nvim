---:checkhealth hangar — reported set, and one CLI probe per adapter.
---@param harness table
return function(harness)
  local check = harness.check

  do
    local hangar = require("hangar")

    -- A stand-in for an installed agent CLI. It has to answer `--version`
    -- successfully: the double-spawn this spec guards against lived in
    -- `version_of(exe) and (" — " .. version_of(exe))`, where a failing probe
    -- short-circuits the `and` and hides the second call.
    local bindir = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-health-XXXXXX"))
    local fake_cli = bindir .. "/hangar-fake-cli"
    local script = assert(io.open(fake_cli, "w"))
    script:write("#!/bin/sh\necho 'fake-cli 1.2.3'\n")
    script:close()
    vim.uv.fs_chmod(fake_cli, tonumber("755", 8))

    -- Real executables, so executable() and the probe behave as they do for a
    -- user: the fake CLI stands in for an installed agent, the `hangar-missing-*`
    -- names for absent ones. `codex` is the default, so its absence must be an
    -- error while the others are only warnings.
    hangar.config.adapter = "codex"
    hangar.config.adapters = {
      claude_code = { cmd = fake_cli },
      codex = { cmd = "hangar-missing-codex" },
      gemini = { cmd = "hangar-missing-gemini" },
      opencode = { cmd = "hangar-missing-opencode" },
    }

    -- count --version spawns per executable; everything still really runs, so
    -- the git checks below behave normally
    local probes = {}
    local real_system = vim.system
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts)
      if type(cmd) == "table" and cmd[2] == "--version" then
        probes[cmd[1]] = (probes[cmd[1]] or 0) + 1
      end
      return real_system(cmd, opts)
    end

    local reported = { ok = {}, warn = {}, error = {} }
    local real_health = vim.health
    vim.health = {
      start = function() end,
      ok = function(msg)
        table.insert(reported.ok, msg)
      end,
      warn = function(msg)
        table.insert(reported.warn, msg)
      end,
      error = function(msg)
        table.insert(reported.error, msg)
      end,
    }

    -- health.lua binds `local health = vim.health` at load, so it must be
    -- required *after* the stub is in place
    package.loaded["hangar.health"] = nil
    local ran, err = pcall(function()
      require("hangar.health").check()
    end)

    vim.system = real_system
    vim.health = real_health
    package.loaded["hangar.health"] = nil

    check(ran, "health: check() runs without error" .. (ran and "" or (": " .. tostring(err))))

    -- #18: version_of spawns a process, and used to be called twice per adapter
    check(probes[fake_cli] == 1, "health: an installed adapter CLI is probed exactly once")
    check(probes.git == 1, "health: git is probed exactly once")
    check(probes["hangar-missing-codex"] == nil, "health: a missing CLI is never spawned")

    local function reported_any(level, pattern)
      for _, msg in ipairs(reported[level]) do
        if tostring(msg):find(pattern, 1, true) then
          return true
        end
      end
      return false
    end

    check(reported_any("ok", "hangar.nvim " .. hangar.version), "health: reports the plugin version")
    check(
      reported_any("ok", ("claude_code: `%s` found — fake-cli 1.2.3"):format(fake_cli)),
      "health: installed adapter reported ok, with its version"
    )
    check(
      reported_any("error", "codex (default adapter): `hangar-missing-codex` not found"),
      "health: missing default adapter is an error"
    )
    check(
      reported_any("warn", "gemini: `hangar-missing-gemini` not found"),
      "health: missing non-default adapter is a warning"
    )
    check(not reported_any("error", "gemini"), "health: a missing non-default adapter is not an error")

    os.remove(fake_cli)
    vim.uv.fs_rmdir(bindir)
  end
end
