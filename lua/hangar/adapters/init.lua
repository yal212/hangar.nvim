---Adapter registry: resolve adapter modules by name and validate the contract.
---Contract: `name` string, `build_cmd(opts) -> argv`, `parse_line(line) -> event|nil`.
local M = {}

---@param name string
---@return table|nil adapter
---@return string|nil err
function M.get(name)
  if type(name) ~= "string" or name == "" then
    return nil, "adapter name required"
  end
  if name == "init" or name == "util" then
    return nil, "not an adapter: " .. name
  end
  local ok, adapter = pcall(require, "hangar.adapters." .. name)
  if not ok then
    return nil, ("unknown adapter %q (available: %s)"):format(name, table.concat(M.available(), ", "))
  end
  if
    type(adapter) ~= "table"
    or type(adapter.name) ~= "string"
    or type(adapter.build_cmd) ~= "function"
    or type(adapter.parse_line) ~= "function"
  then
    return nil, ("adapter %q does not implement the contract (name, build_cmd, parse_line)"):format(name)
  end
  return adapter
end

---Names of all adapters shipped on the runtimepath.
---@return string[]
function M.available()
  local names = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/hangar/adapters/*.lua", true)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    if name ~= "init" and name ~= "util" and not vim.list_contains(names, name) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

return M
