---Telescope extension. Telescope is not a dependency and CI does not install
---it, so a skip-if-absent test would never actually run — the host modules are
---stubbed here instead, which is also what lets the spec assert on the finder
---and the mappings the extension builds. The stubs are deliberately local to
---this spec (not tests/harness.lua) so no other spec sees a fake telescope.
---@param harness table
return function(harness)
  local check, sh = harness.check, harness.sh
  local runner = require("hangar.runner")
  local hangar_pickers = require("hangar.pickers")

  local captured -- the config the extension hands telescope.pickers.new()
  local found = 0 -- times :find() was called
  local closed = {} -- prompt bufnrs passed to actions.close()
  local selected -- what action_state.get_selected_entry() returns
  local default_handlers = {} -- handlers passed to select_default:replace()
  local mapped = {} -- telescope key -> { modes, handler }

  local STUBS = {
    ["telescope"] = {
      register_extension = function(ext)
        return ext
      end,
    },
    ["telescope.pickers"] = {
      new = function(opts, cfg)
        captured = { opts = opts, cfg = cfg }
        return {
          find = function()
            found = found + 1
          end,
        }
      end,
    },
    ["telescope.finders"] = {
      new_table = function(cfg)
        return { _finder = cfg }
      end,
    },
    ["telescope.config"] = {
      values = {
        generic_sorter = function()
          return "sorter"
        end,
      },
    },
    ["telescope.actions"] = {
      close = function(bufnr)
        closed[#closed + 1] = bufnr
      end,
      select_default = {
        replace = function(_, handler)
          default_handlers[#default_handlers + 1] = handler
        end,
      },
    },
    ["telescope.actions.state"] = {
      get_selected_entry = function()
        return selected
      end,
    },
  }
  for name, mod in pairs(STUBS) do
    package.preload[name] = function()
      return mod
    end
  end

  local repo = harness.git_repo("telescope")
  sh(repo, { "git", "commit", "--allow-empty", "-m", "init" })
  local prev = assert(vim.uv.cwd())
  vim.fn.chdir(repo)
  local root = assert(require("hangar.worktree").root())

  runner.runs["ts1"] = {
    id = "ts1",
    root = root,
    status = "done",
    started = 1,
    events = {},
    prompt = "make   the\ntests green",
    cost = 0.75,
    turns = 2,
  }

  package.loaded["telescope._extensions.hangar"] = nil
  local ext = require("telescope._extensions.hangar")

  check(type(ext.exports.runs) == "function", "telescope: the extension exports `runs`")
  check(ext.exports.hangar == ext.exports.runs, "telescope: `:Telescope hangar` and `hangar runs` are the same picker")

  ext.exports.runs({})
  check(found == 1, "telescope: the picker is actually opened")
  check(captured and captured.cfg.prompt_title == "hangar runs", "telescope: the prompt is titled")
  check(captured and captured.cfg.sorter == "sorter", "telescope: the configured generic_sorter is used")

  -- entry_maker: what telescope displays and searches over
  local finder = captured.cfg.finder._finder
  check(#finder.results == 1, "telescope: one finder result per run in this repo")
  local entry = finder.entry_maker(finder.results[1])
  check(entry.value.run.id == "ts1", "telescope: the entry carries the run through as its value")
  check(entry.display == finder.results[1].display, "telescope: the entry displays the shared picker line")
  check(entry.ordinal:find("ts1", 1, true) ~= nil, "telescope: the ordinal is searchable by run id")
  check(entry.ordinal:find("done", 1, true) ~= nil, "telescope: the ordinal is searchable by status")
  check(entry.ordinal:find("make   the\ntests green", 1, true) ~= nil, "telescope: the ordinal is searchable by prompt")

  -- attach_mappings: one default, the rest bound at their declared keys.
  -- Driven off hangar.pickers.actions so adding an action cannot silently skip
  -- this frontend.
  local function map(modes, lhs, handler)
    mapped[lhs] = { modes = modes, handler = handler }
  end
  check(captured.cfg.attach_mappings(1, map) == true, "telescope: attach_mappings keeps the default mappings")
  check(#default_handlers == 1, "telescope: exactly one action replaces select_default")
  for _, action in ipairs(hangar_pickers.actions) do
    if action.default then
      check(
        mapped[action.telescope] == nil,
        ("telescope: the default action (%s) is not also mapped"):format(action.name)
      )
    else
      local bound = mapped[action.telescope]
      check(bound ~= nil, ("telescope: %s is bound to %s"):format(action.name, action.telescope))
      check(
        bound and vim.deep_equal(bound.modes, { "i", "n" }),
        ("telescope: %s is bound in both insert and normal mode"):format(action.name)
      )
    end
  end

  -- driving the default handler must close the picker and run the action for
  -- the selected entry — here, opening that run's transcript
  selected = { value = { run = runner.runs.ts1 } }
  default_handlers[1]()
  check(vim.deep_equal(closed, { 1 }), "telescope: selecting closes the picker with its prompt bufnr")
  local transcript_buf
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf):find("hangar://transcript/ts1", 1, true) then
      transcript_buf = buf
    end
  end
  check(transcript_buf ~= nil, "telescope: the default action opens the selected run's transcript")
  if transcript_buf then
    for _, win in ipairs(vim.fn.win_findbuf(transcript_buf)) do
      vim.api.nvim_win_close(win, true)
    end
  end

  -- nothing selected: the handler must not call the action with a nil run
  selected = nil
  found, closed = 0, {}
  local ok_nil = pcall(default_handlers[1])
  check(ok_nil, "telescope: selecting nothing does not raise")

  -- outside a git repo, the picker reports why instead of building a finder
  vim.fn.chdir(prev)
  local tmp = assert(vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/hangar-ts-norepo-XXXXXX"))
  vim.fn.chdir(tmp)
  captured, found = nil, 0
  local notified
  local real_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    notified = msg
  end
  local ok_norepo = pcall(ext.exports.runs, {})
  vim.notify = real_notify
  check(ok_norepo and found == 0 and captured == nil, "telescope: outside a repo no picker is built or opened")
  check(notified ~= nil, "telescope: outside a repo the failure is reported")
  vim.fn.chdir(prev)

  runner.runs["ts1"] = nil
  package.loaded["telescope._extensions.hangar"] = nil
  for name in pairs(STUBS) do
    package.preload[name] = nil
    package.loaded[name] = nil
  end
end
