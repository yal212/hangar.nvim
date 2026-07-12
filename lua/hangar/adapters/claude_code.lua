---Adapter for the Claude Code CLI (`claude -p --output-format stream-json`).
---Adapter contract: `name`, `build_cmd(opts) -> argv`, `parse_line(line) -> event|nil`.
local M = { name = "claude_code" }

---@class hangar.SpawnCmdOpts
---@field prompt string
---@field permission_mode "acceptEdits"|"bypassPermissions"
---@field model string|nil
---@field claude_cmd string|nil

---@param opts hangar.SpawnCmdOpts
---@return string[]
function M.build_cmd(opts)
  local cmd = {
    opts.claude_cmd or "claude",
    "-p",
    opts.prompt,
    "--output-format",
    "stream-json",
    "--verbose",
    "--no-session-persistence",
    "--permission-mode",
    opts.permission_mode,
  }
  if opts.model then
    vim.list_extend(cmd, { "--model", opts.model })
  end
  return cmd
end

local function is_tbl(v)
  return type(v) == "table"
end

---Summarize a tool_use input table into a short single-line string.
local function input_summary(input)
  if not is_tbl(input) then
    return ""
  end
  for _, key in ipairs({ "file_path", "path", "pattern", "command", "prompt", "query", "url" }) do
    local v = input[key]
    if type(v) == "string" and v ~= "" then
      local s = v:gsub("%s+", " ")
      if #s > 60 then
        s = s:sub(1, 57) .. "..."
      end
      return s
    end
  end
  return ""
end

---Parse one stream-json line into a normalized event, or nil to skip.
---Normalized kinds: "init", "text", "tool_use", "tool_result", "result".
---@param line string
---@return table|nil event
function M.parse_line(line)
  if line == "" then
    return nil
  end
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or not is_tbl(obj) then
    return nil
  end

  if obj.type == "system" and obj.subtype == "init" then
    return { kind = "init", model = obj.model, session_id = obj.session_id }
  end

  if obj.type == "assistant" and is_tbl(obj.message) and is_tbl(obj.message.content) then
    -- One assistant message can hold several blocks; return them as a batch.
    local batch = {}
    for _, block in ipairs(obj.message.content) do
      if block.type == "text" and type(block.text) == "string" and block.text ~= "" then
        batch[#batch + 1] = { kind = "text", text = block.text }
      elseif block.type == "tool_use" then
        batch[#batch + 1] = {
          kind = "tool_use",
          tool = block.name or "?",
          summary = input_summary(block.input),
        }
      end
    end
    if #batch > 0 then
      return { kind = "batch", events = batch }
    end
    return nil
  end

  if obj.type == "user" and is_tbl(obj.message) and is_tbl(obj.message.content) then
    for _, block in ipairs(obj.message.content) do
      if block.type == "tool_result" then
        local text = ""
        if type(block.content) == "string" then
          text = block.content
        elseif is_tbl(block.content) then
          for _, part in ipairs(block.content) do
            if part.type == "text" and type(part.text) == "string" then
              text = text .. part.text
            end
          end
        end
        text = text:gsub("%s+", " ")
        if #text > 120 then
          text = text:sub(1, 117) .. "..."
        end
        return { kind = "tool_result", text = text, is_error = block.is_error == true }
      end
    end
    return nil
  end

  if obj.type == "result" then
    return {
      kind = "result",
      is_error = obj.is_error == true,
      subtype = obj.subtype,
      cost = tonumber(obj.total_cost_usd),
      turns = tonumber(obj.num_turns),
      duration_ms = tonumber(obj.duration_ms),
      text = type(obj.result) == "string" and obj.result or nil,
    }
  end

  return nil -- unknown event types are ignored; the CLI adds types over time
end

return M
