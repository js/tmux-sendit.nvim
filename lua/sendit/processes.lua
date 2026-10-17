local M = {}

---@class sendit.ProcessID
---@field patterns string[] Lua patterns matched against a process's argv, name and paths
---@field exclude? string[] Lua patterns; if any matches the same process then it is rejected

---@type table<string, sendit.ProcessID>
local registry = {
  claude = { patterns = { "claude" } },
  codex = { patterns = { "codex" } },
  opencode = { patterns = { "opencode" } },
  gemini = { patterns = { "gemini" } },
  copilot = { patterns = { "copilot" }, exclude = { "language%-server" } },
  pi = { patterns = { "[/%s]pi$", "[/%s]pi%s", "pi " } },
}

---returns true if cmd matches any of the patterns
---@param cmd string
---@params patterns string[]
---@return boolean
local function any_match(cmd, patterns)
  for _, p in ipairs(patterns or {}) do
    if cmd:match(p) then
      return true
    end
  end
  return false
end

---@param strings string[] metadata of one process
---@param name string
---@param ident sendit.ProcessID
---@return boolean
local function ident_matches(strings, name, ident)
  local hit = false
  for _, str in ipairs(strings) do
    if any_match(str, ident.exclude) then
      return false
    end
    hit = hit or str:match("[^/]*$") == name or any_match(str, ident.patterns)
  end
  return hit
end

---Name of the first registry entry in `names` that matches one of `procs`
---@param procs string[][] metadata strings of each process, such as argv, name and paths
---@param names string[]
---@return string?
local function identify(procs, names)
  for _, name in ipairs(names) do
    for _, strings in ipairs(procs) do
      if ident_matches(strings, name, registry[name]) then
        return name
      end
    end
  end
end

---Targets of the active backend that run a process matching one of `names`
---in the built-in registry. Excludes the editor's own pane or block.
---@param names string[]
---@return table[]
function M.filter(names)
  names = vim.tbl_filter(function(name)
    if registry[name] then
      return true
    end
    vim.notify("sendit: unknown process name '" .. tostring(name) .. "'", vim.log.levels.WARN)
    return false
  end, names)
  if #names == 0 then
    return {}
  end

  local targets = require("sendit.targets")
  local backend, err = targets.resolve()
  local rows
  if backend then
    rows, err = backend.list(targets.scope())
  end
  if not rows then
    error(err, 0)
  end

  local procs = backend.process_strings(rows)
  return vim.tbl_filter(function(row)
    row.agent = identify(procs[row], names)
    return row.agent ~= nil
  end, rows)
end

return M
