local config = require("sendit.config")

---@class sendit.Backend
---@field name "tmux"|"rex"
---@field env string[] environment variables that must be set to use the backend
---@field list fun(scope: "window"|"session"|"all"): table[]?, string? targets in scope, without the editor's own
---@field process_strings fun(targets: table[]): table<table, string[][]> per target, the metadata strings of each of its processes
---@field key fun(target: table): string? stable identity, nil when the table is not a target of this backend
---@field send_argv fun(target: table, text: string): string[]
---@field focus_argv fun(target: table): string[]
---@field is_self? fun(target: table): boolean drops the editor from process_filter results

local M = {}

local auto_order = { "tmux", "rex" }

local function failure(result)
  if (result.signal or 0) ~= 0 then
    return "terminated by signal " .. result.signal
  end
  if result.code ~= 0 then
    return ("exit code %s: %s"):format(result.code, vim.trim(result.stderr or ""))
  end
end

---@param argv string[]
---@return string? stdout, string? err
function M.run(argv)
  local ok, result = pcall(function()
    return vim.system(argv, { text = true }):wait(5000)
  end)
  if not ok then
    return nil, table.concat(argv, " ") .. ": " .. tostring(result)
  end
  local err = failure(result)
  if err then
    return nil, table.concat(argv, " ") .. " failed: " .. err
  end
  return result.stdout or ""
end

---@return sendit.Backend?, string?
function M.resolve()
  local wanted = config.config.backend
  local names = wanted == "auto" and auto_order or vim.tbl_contains(auto_order, wanted) and { wanted }
  if not names then
    return nil, "invalid backend '" .. tostring(wanted) .. "'"
  end
  for _, name in ipairs(names) do
    local backend = require("sendit." .. name)
    if vim.iter(backend.env):all(function(var)
      return (vim.env[var] or "") ~= ""
    end) then
      return backend
    end
  end
  if wanted == "auto" then
    return nil, "not inside tmux ($TMUX) or a Rex block ($REX_SESSION and $REX_BLOCK)"
  end
  return nil, "backend '" .. wanted .. "' needs $" .. table.concat(require("sendit." .. wanted).env, " and $")
end

---@return "window"|"session"|"all"
function M.scope()
  local scope = config.config.pane_scope
  if scope == "window" or scope == "session" or scope == "all" then
    return scope
  end
  vim.notify("sendit: invalid pane_scope '" .. tostring(scope) .. "', falling back to 'session'", vim.log.levels.WARN)
  return "session"
end

---@param backend sendit.Backend
---@return table[]?, string?
local function candidates(backend)
  local filter = config.config.process_filter
  if type(filter) ~= "function" then
    return backend.list(M.scope())
  end
  local ok, result = pcall(filter)
  if not ok then
    return nil, tostring(result)
  end
  if result ~= nil and not (type(result) == "table" and vim.islist(result)) then
    return nil, "process_filter must return a list of targets, got " .. type(result)
  end
  local rows, dropped = {}, 0
  for _, row in ipairs(result or {}) do
    if type(row) ~= "table" or not backend.key(row) then
      dropped = dropped + 1
    elseif not (backend.is_self and backend.is_self(row)) then
      table.insert(rows, row)
    end
  end
  if dropped > 0 then
    vim.notify(
      ("Sendit: ignored %d process_filter entries that are not %s targets"):format(dropped, backend.name),
      vim.log.levels.WARN
    )
  end
  return rows
end

local function remembered(backend, rows)
  local legacy = backend.name == "tmux" and vim.g.sendit_pane
  if legacy then
    vim.g.sendit_pane = nil
    for _, row in ipairs(rows) do
      if row.id == legacy then
        vim.g.sendit_target = { backend = backend.name, key = backend.key(row) }
      end
    end
  end

  local saved = vim.g.sendit_target
  if not saved or saved.backend ~= backend.name then
    return nil
  end
  for _, row in ipairs(rows) do
    if backend.key(row) == saved.key then
      return row
    end
  end
  vim.g.sendit_target = nil
end

local function display(row)
  return row.id or row.block_id
end

local function deliver(backend, row, text)
  if config.config.remember_last then
    vim.g.sendit_target = { backend = backend.name, key = backend.key(row) }
  end
  local argv = backend.send_argv(row, text)
  local ok, err = pcall(vim.system, argv, { text = true }, function(result)
    local send_err = failure(result)
    if send_err then
      vim.schedule(function()
        vim.notify("sendit: command failed: " .. send_err, vim.log.levels.ERROR)
      end)
      return
    end
    if config.config.focus_after_send then
      local function focus_failed(detail)
        vim.schedule(function()
          vim.notify("Sendit: text sent, but focus failed: " .. detail, vim.log.levels.WARN)
        end)
      end
      local focused, focus_err = pcall(vim.system, backend.focus_argv(row), {}, function(focus_result)
        local detail = failure(focus_result)
        if detail then
          focus_failed(detail)
        end
      end)
      if not focused then
        focus_failed(tostring(focus_err))
      end
    end
    vim.schedule(function()
      vim.notify("Sent to '" .. display(row) .. "'")
    end)
  end)
  if not ok then
    vim.notify("sendit: command failed: " .. argv[1] .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
end

local function label(row)
  return row.agent or row.command or ""
end

---@param text string
function M.send(text)
  local backend, err = M.resolve()
  local rows
  if backend then
    rows, err = candidates(backend)
  end
  if not rows then
    vim.notify("Sendit: " .. err, vim.log.levels.ERROR)
    return
  end

  local hit = config.config.remember_last and remembered(backend, rows)
  if hit then
    return deliver(backend, hit, text)
  end
  if #rows == 0 then
    vim.notify("Sendit: no target panes available", vim.log.levels.WARN)
    return
  end
  if #rows == 1 then
    return deliver(backend, rows[1], text)
  end

  local widths = { label = 0, id = 0 }
  for _, row in ipairs(rows) do
    widths.label = math.max(widths.label, #label(row))
    widths.id = math.max(widths.id, #display(row))
  end
  local function pad(str, width)
    return str .. string.rep(" ", width - #str)
  end

  vim.ui.select(rows, {
    prompt = "Select target " .. (backend.name == "rex" and "Rex block:" or "tmux pane:"),
    format_item = function(row)
      return pad(label(row), widths.label) .. " " .. pad(display(row), widths.id)
    end,
  }, function(choice)
    if choice then
      deliver(backend, choice, text)
    end
  end)
end

function M.reset()
  if vim.g.sendit_target or vim.g.sendit_pane then
    vim.g.sendit_target = nil
    vim.g.sendit_pane = nil
    vim.notify("Sendit: target selection cleared")
  else
    vim.notify("Sendit: no target was set", vim.log.levels.INFO)
  end
end

return M
