local M = {}

local config = require("sendit.config")

local scope_flags = {
  window = "",
  session = " -s ",
  all = " -a ",
}

---@return string command
function M.list_command()
  local scope = config.config.pane_scope
  local flag = scope_flags[scope]
  if not flag then
    vim.notify("sendit: invalid pane_scope '" .. tostring(scope) .. "', falling back to 'session'", vim.log.levels.WARN)
    flag = scope_flags.session
  end
  return "tmux list-panes"
    .. flag
    .. " -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'"
end

---@param text string
---@param pane_id string
---@return string[] command
function M.send_command(text, pane_id)
  local cmd = vim.list_extend(vim.list_slice(config.config.cmd), { pane_id, text })
  return cmd
end

---@param pane_id string
---@return string[] command
function M.focus_command(pane_id)
  return { "tmux", "select-pane", "-t", pane_id }
end

return M
