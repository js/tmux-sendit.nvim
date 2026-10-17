local run = require("sendit.targets").run

---@class sendit.RexBlock
---@field session string owning session id
---@field block_id string
---@field window_id? string
---@field id string display label
---@field command? string block label or flavor
---@field agent? string registry name of the matched coding-agent process

---@type sendit.Backend
local M = { name = "rex", env = { "REX_SESSION", "REX_BLOCK" } }

local function json(argv)
  local out, err = run(argv)
  if not out then
    return nil, err
  end
  local ok, data = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
  if ok and type(data) == "table" then
    return data
  end
  return nil, table.concat(argv, " ") .. " returned invalid JSON"
end

---@return boolean `rows` is a list of tables whose `required` fields are strings and `optional` fields strings or nil
local function valid(rows, required, optional)
  if type(rows) ~= "table" or not vim.islist(rows) then
    return false
  end
  return vim.iter(rows):all(function(row)
    return type(row) == "table"
      and vim.iter(required):all(function(f)
        return type(row[f]) == "string"
      end)
      and vim.iter(optional):all(function(f)
        return row[f] == nil or type(row[f]) == "string"
      end)
  end)
end

---@return sendit.RexBlock[]?, string?
local function blocks(session, session_label)
  local data, err = json({ "rex", "block", "ls", "-s", session, "--json" })
  if not data then
    return nil, err
  end
  if not valid(data.blocks, { "block_id" }, { "label", "flavor", "window_id" }) then
    return nil, "rex block ls -s " .. session .. " returned a malformed block list"
  end
  return vim.tbl_map(function(b)
    local name = (b.label or "block") .. " #" .. b.block_id:sub(-4)
    return {
      session = session,
      block_id = b.block_id,
      window_id = b.window_id,
      id = session_label and (session_label .. "/" .. name) or name,
      command = b.label or b.flavor,
    }
  end, data.blocks)
end

function M.is_self(block)
  return block.session == vim.env.REX_SESSION and block.block_id == vim.env.REX_BLOCK
end

function M.list(scope)
  local sessions = { { session_id = vim.env.REX_SESSION } }
  if scope == "all" then
    local data, err = json({ "rex", "ls", "--json" })
    if not data then
      return nil, err
    end
    if not valid(data.sessions, { "session_id" }, { "label" }) then
      return nil, "rex ls returned a malformed session list"
    end
    sessions = data.sessions
  end

  local rows = {}
  for _, s in ipairs(sessions) do
    local found, err = blocks(s.session_id, s.label)
    if not found then
      return nil, err
    end
    vim.list_extend(rows, found)
  end

  if scope == "window" then
    local editor = vim.iter(rows):find(M.is_self)
    if not (editor and editor.window_id) then
      return nil, "editor block " .. vim.env.REX_BLOCK .. " not found in session " .. vim.env.REX_SESSION
    end
    rows = vim.tbl_filter(function(b)
      return b.window_id == editor.window_id
    end, rows)
  end

  return vim.tbl_filter(function(b)
    return not M.is_self(b)
  end, rows)
end

local process_fields = { "name", "argv0", "path", "invoked_path", "script" }

function M.process_strings(rows)
  local procs, failed = {}, 0
  for _, row in ipairs(rows) do
    local data = json({ "rex", "block", "call", "-s", row.session, "-b", row.block_id, "process" })
    procs[row] = {}
    if data then
      local list = vim.list_extend(
        { data.foreground or false, data.child or false },
        type(data.ancestors) == "table" and data.ancestors or {}
      )
      for _, p in ipairs(list) do
        if type(p) == "table" then
          local strings = {}
          for _, field in ipairs(process_fields) do
            if type(p[field]) == "string" then
              table.insert(strings, p[field])
            end
          end
          table.insert(procs[row], strings)
        end
      end
    else
      failed = failed + 1
    end
  end
  if failed > 0 then
    vim.notify(("Sendit: could not read the process of %d Rex block(s)"):format(failed), vim.log.levels.WARN)
  end
  return procs
end

function M.key(block)
  if type(block.session) == "string" and type(block.block_id) == "string" then
    return block.session .. "\n" .. block.block_id
  end
end

function M.send_argv(block, text)
  return { "rex", "send", "-s", block.session, "-b", block.block_id, "--", text }
end

function M.focus_argv(block)
  return { "rex", "focus", "-s", block.session, block.block_id }
end

return M
