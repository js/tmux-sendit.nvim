local M = {}

local config = require("sendit.config").config

---@return string command
function M.list_command()
  local param = config.only_current_session and " -s " or ""
  return "tmux list-panes" .. param .. "-F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'"
end

---@param text string
---@param pane_id string
---@return string[] command
function M.send_command(text, pane_id)
  local cmd = vim.list_extend(vim.list_slice(config.cmd), { pane_id, text })
  return cmd
end

return M
