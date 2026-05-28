---@class sendit.TmuxModule
---@field list_command fun(): string
---@field send_command fun(text: string, pane_id: string): string[]
---@field focus_command fun(pane_id: string): string[]
---@field use_pane fun(pane_id: string, on_select: fun(pane_id: string))
---@field select_pane fun(on_select: fun(pane_id: string))
---@field send_to_pane fun(text: string, pane_id: string)
local M = {}

---@type sendit.ConfigModule
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

---@param pane_id string
---@param on_select fun(pane_id: string)
function M.use_pane(pane_id, on_select)
  if config.config.remember_last then
    vim.g.sendit_pane = pane_id
  end
  on_select(pane_id)
end

---@param on_select fun(pane_id: string)
function M.select_pane(on_select)
  ---@type sendit.Pane[]
  local panes
  if type(config.config.process_filter) == "function" then
    panes = config.config.process_filter() or {}
  else
    local all_panes = vim.fn.systemlist(M.list_command())
    ---@type string?
    local current_pane = vim.env.TMUX_PANE
    panes = vim
      .iter(all_panes)
      :map(function(pane)
        ---@type string?, string?, string?
        local tmux_id, id, rest = pane:match("^(%S+)%s(%S+)%s(.+)$")
        if not (tmux_id and id and rest) then
          return nil
        end
        ---@type sendit.Pane
        return { tmux_id = tmux_id, id = id, command = rest }
      end)
      :filter(function(pane)
        return not current_pane or pane.tmux_id ~= current_pane
      end)
      :totable()
  end

  -- Reuse remembered pane if it still exists and config says so
  local remembered = vim.g.sendit_pane
  if remembered then
    for _, pane in ipairs(panes) do
      if pane.id == remembered then
        return on_select(remembered)
      end
    end
    vim.g.sendit_pane = nil
  end

  -- Auto-select if only one pane available
  if #panes == 1 then
    return M.use_pane(panes[1].id, on_select)
  end

  if #panes == 0 then
    vim.notify("Sendit: no target panes available", vim.log.levels.WARN)
    return
  end

  local widths = { command_name = 0, id = 0 }
  for _, p in ipairs(panes) do
    widths.command_name = math.max(widths.command_name, #(p.agent or p.command))
    widths.id = math.max(widths.id, #p.id)
  end

  local function pad(str, width)
    return str .. string.rep(" ", width - #str)
  end

  vim.ui.select(panes, {
    prompt = "Select target tmux pane:",
    ---@param pane sendit.Pane
    format_item = function(pane)
      return table.concat({
        pad(pane.agent and pane.agent or pane.command, widths.command_name),
        pad(pane.id, widths.id),
      }, " ")
    end,
  }, function(choice)
    if choice then
      M.use_pane(choice.id, on_select)
    end
  end)
end

---@param text string
---@param pane_id string
function M.send_to_pane(text, pane_id)
  local cmd = M.send_command(text, pane_id)
  vim.system(cmd, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("sendit: command failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      end)
    else
      if config.config.focus_after_send then
        vim.system(M.focus_command(pane_id))
      end
      vim.schedule(function()
        vim.notify("Sent to pane '" .. pane_id .. "'")
      end)
    end
  end)
end

return M
