local config = require("sendit.config")
local run = require("sendit.targets").run

---@class sendit.Pane
---@field tmux_id? string tmux's internal pane id (e.g. "%53")
---@field id string human-readable session:window.pane id (e.g. "_config:3.3")
---@field command? string the pane's foreground command (#{pane_current_command})
---@field pane_tty? string absolute tty path (e.g. "/dev/ttys052")
---@field agent? string registry name of the matched coding-agent process

---@type sendit.Backend
local M = { name = "tmux", env = { "TMUX" } }

local scope_flags = {
  window = {},
  session = { "-s" },
  all = { "-a" },
}

function M.list(scope)
  local argv = vim.list_extend({ "tmux", "list-panes" }, scope_flags[scope])
  if scope ~= "all" and vim.env.TMUX_PANE then
    vim.list_extend(argv, { "-t", vim.env.TMUX_PANE })
  end
  vim.list_extend(
    argv,
    { "-F", "#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_tty} #{pane_current_command}" }
  )
  local out, err = run(argv)
  if not out then
    return nil, err
  end
  local panes = {}
  for line in vim.gsplit(out, "\n", { trimempty = true }) do
    local tmux_id, id, tty, cmd = line:match("^(%S+)%s(%S+)%s(%S+)%s(.+)$")
    if not (tmux_id and tmux_id:match("^%%%d+$")) then
      return nil, "tmux list-panes returned a malformed pane list"
    end
    if tmux_id ~= vim.env.TMUX_PANE then
      table.insert(panes, { tmux_id = tmux_id, id = id, pane_tty = tty, command = cmd })
    end
  end
  return panes
end

function M.process_strings(panes)
  local by_tty = {}
  local out, err = run({ "ps", "-axo", "tty=,command=" })
  if not out then
    vim.notify("Sendit: could not list processes: " .. err, vim.log.levels.WARN)
    out = ""
  end
  for line in vim.gsplit(out, "\n", { trimempty = true }) do
    local tty, cmd = line:match("^%s*(%S+)%s+(.+)$")
    if tty and tty:sub(1, 1) ~= "?" then
      by_tty[tty] = by_tty[tty] or {}
      table.insert(by_tty[tty], { cmd })
    end
  end
  local procs = {}
  for _, pane in ipairs(panes) do
    procs[pane] = by_tty[(pane.pane_tty or ""):gsub("^/dev/", "")] or {}
  end
  return procs
end

function M.key(pane)
  if pane.session == nil and pane.block_id == nil and type(pane.id) == "string" and pane.id ~= "" then
    return pane.tmux_id or pane.id
  end
end

function M.send_argv(pane, text)
  if config.config.cmd then
    return vim.list_extend(vim.list_slice(config.config.cmd), { pane.id, text })
  end
  return { "tmux", "send-keys", "-l", "-t", pane.tmux_id or pane.id, "--", text }
end

function M.focus_argv(pane)
  return { "tmux", "select-pane", "-t", pane.tmux_id or pane.id }
end

return M
