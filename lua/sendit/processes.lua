local M = {}

---@type sendit.ConfigModule
local config = require("sendit.config")

local scope_flags = {
  window = "",
  session = " -s ",
  all = " -a ",
}

---@class sendit.ProcessID
---@field patterns string[] Lua patterns matched against full argv of a process on the panes tty
---@field exclude? string[] Lua patterns; if any matches then the candidate is rejected

---@class sendit.Pane
---@field tmux_id string tmux's internal pane id (e.g. "%53")
---@field id string human-readable session:window.pane id (e.g. "_config:3.3")
---@field command string the pane's foreground command (#{pane_current_command})
---@field pane_tty string absolute tty path (e.g. "/dev/ttys052")
---@field agent string registry name of the matched coding-agent process (set by M.filter)

---@type table<string, sendit.ProcessID>
local registry = {
  claude = { patterns = { "claude" } },
  codex = { patterns = { "codex" } },
  opencode = { patterns = { "opencode" } },
  gemini = { patterns = { "gemini" } },
  copilot = { patterns = { "copilot" }, exclude = { "language%-server" } },
  pi = { patterns = { "[/%s]pi$", "[/%s]pi%s", "pi " } },
}

---@return string command
local function list_panes_command()
  local scope = config.config.pane_scope
  local flag = scope_flags[scope] or scope_flags.session
  return "tmux list-panes"
    .. flag
    .. " -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_tty} #{pane_current_command}'"
end

---Group process command line by tty (tty without the /dev/ prefix)
---@return table<string, string[]>
local function cmds_by_tty()
  ---@type table<string, string[]>
  local out = {}
  for _, line in ipairs(vim.fn.systemlist("ps -axo tty=,command=")) do
    local tty, cmd = line:match("^(%S+)%s+(.+)$")
    if tty and tty:sub(1, 1) ~= "?" then -- not starts with "?"
      out[tty] = out[tty] or {}
      table.insert(out[tty], cmd)
    end
  end
  return out
end

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

---@param cmds string[]
---@param ident sendit.ProcessID
---@return boolean
local function ident_matches(cmds, ident)
  for _, cmd in ipairs(cmds) do
    if any_match(cmd, ident.patterns) and not any_match(cmd, ident.exclude) then
      return true
    end
  end
  return false
end

---Filter tmux panes to those whose ttys hosts a process matching one of `names`
---in the built-in registry
---@param names string[]
---@return sendit.Pane[]
function M.filter(names)
  ---@type { name: string, ident: sendit.ProcessID }[]
  local idents = {}
  for _, name in ipairs(names) do
    local ident = registry[name]
    if ident then
      table.insert(idents, { name = name, ident = ident })
    else
      vim.notify("sendit: unknown process name '" .. tostring(name) .. "'", vim.log.levels.WARN)
    end
  end

  if #idents == 0 then
    return {}
  end

  ---@type string?
  local current_pane = vim.env.TMUX_PANE
  local raw = vim.fn.systemlist(list_panes_command())
  ---@type sendit.Pane[]
  local panes = {}
  for _, line in ipairs(raw) do
    -- line looks like:
    -- %53 _config:3.3 /dev/ttys052 2.1.123
    local tmux_id, id, tty, cmd = line:match("^(%S+)%s(%S+)%s(%S+)%s(.+)$")
    if tmux_id and (not current_pane or tmux_id ~= current_pane) then
      table.insert(panes, {
        tmux_id = tmux_id,
        id = id,
        command = cmd,
        pane_tty = tty,
        agent = cmd, -- will be resolved next
      })
    end
  end
  if #panes == 0 then
    return {}
  end

  local cmds = cmds_by_tty()
  ---@type sendit.Pane[]
  local matching_panes = {}
  for _, pane in ipairs(panes) do
    local tty_key = pane.pane_tty:gsub("^/dev/", "")
    local pane_cmds = cmds[tty_key] or {}
    for _, entry in ipairs(idents) do
      if ident_matches(pane_cmds, entry.ident) then
        pane.agent = entry.name
        table.insert(matching_panes, pane)
        break
      end
    end
  end

  return matching_panes
end

return M
