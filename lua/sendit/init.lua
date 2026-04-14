local M = {}

local paths = require("sendit.paths")
local tmux = require("sendit.tmux")
local config = require("sendit.config")

M.config = config.config

---@param opts? sendit.Config
function M.setup(opts)
  config.setup(opts)
  M.config = config.config

  local subcommands = {
    selection = M.send_selection,
    path = M.send_rel_path,
    fullpath = M.send_abs_path,
    diagnostic = M.send_diagnostic,
    reset = M.reset_pane,
  }

  vim.api.nvim_create_user_command("Sendit", function(args)
    local sub = args.fargs[1]
    local fn = subcommands[sub]
    if fn then
      if sub == "selection" and args.range > 0 then
        -- we got a line range from the command line
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        local lines = vim.fn.getregion(start_pos, end_pos, { type = vim.fn.visualmode() })
        local text = M._surround_selection(lines)
        M.send_text(text)
      else
        fn()
      end
    else
      vim.notify("Sendit: unknown subcommand '" .. (sub or "") .. "'", vim.log.levels.ERROR)
    end
  end, {
    nargs = 1, -- number of args the Sendit command takes
    complete = function() -- autocomplete
      return vim.tbl_keys(subcommands)
    end,
    desc = "Sendit commands",
    range = true,
  })
end

---@param pane_id string
---@param on_select fun(pane_id: string)
local function use_pane(pane_id, on_select)
  vim.g.sendit_pane = pane_id
  on_select(pane_id)
end

---@param on_select fun(pane_id: string)
local function select_pane(on_select)
  local all_panes = vim.fn.systemlist(tmux.list_command())
  local current_pane = vim.env.TMUX_PANE
  local panes = vim
    .iter(all_panes)
    :map(function(pane)
      local tmux_id, id, rest = pane:match("^(%S+)%s(%S+)%s(.+)$")
      return { tmux_id = tmux_id, id = id, command = rest }
    end)
    :filter(function(pane)
      return not current_pane or pane.tmux_id ~= current_pane
    end)
    :totable()

  -- Reuse remembered pane if it still exists
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
    return use_pane(panes[1].id, on_select)
  end

  if #panes == 0 then
    vim.notify("Sendit: no target panes available", vim.log.levels.WARN)
    return
  end

  vim.ui.select(panes, {
    prompt = "Select target tmux pane:",
    format_item = function(pane)
      return pane.id .. " " .. pane.command
    end,
  }, function(choice)
    if choice then
      use_pane(choice.id, on_select)
    end
  end)
end

---@param text string
---@param pane_id string
local function send_to_pane(text, pane_id)
  local cmd = tmux.send_command(text, pane_id)
  vim.system(cmd, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("sendit: command failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      end)
    else
      if config.config.focus_after_send then
        vim.system(tmux.focus_command(pane_id))
      end
      vim.schedule(function()
        vim.notify("Sent to pane '" .. pane_id .. "'")
      end)
    end
  end)
end

--- @param selection string[] the selection
--- @return string the selection surrounded by prefix+suffix and joined as a string
function M._surround_selection(selection)
  local lines = { M.config.selection_prefix }
  vim.list_extend(lines, selection)
  table.insert(lines, M.config.selection_suffix)
  return table.concat(lines, "\n")
end

-- API

-- Send the diagnostics at the current cursor in the current selection
function M.send_diagnostic()
  local mode = vim.fn.mode()
  local diags

  if mode:match("[vV]") then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    -- handle whether if selecting up or down, getpos returns [bufnum, lnum, col, off]
    local start_line = math.min(start_pos[2], end_pos[2]) - 1
    local end_line = math.max(start_pos[2], end_pos[2]) - 1
    local all_diags = vim.diagnostic.get(0)

    diags = vim.tbl_filter(function(d)
      return d.lnum <= end_line and (d.end_lnum or d.lnum) >= start_line
    end, all_diags)
  else
    local cursor = vim.api.nvim_win_get_cursor(0)
    diags = vim.diagnostic.get(0, { lnum = cursor[1] - 1 })
  end

  local rel_path = paths.get_relative_path()

  local lines = vim
    .iter(diags)
    :map(function(d)
      local severity = vim.diagnostic.severity[d.severity] or "UNKNOWN"
      local source = d.source or "unknown"
      local msg = (d.message or ""):gsub("\n", "")
      return rel_path .. ":" .. (d.lnum + 1) .. ": " .. severity .. " (" .. source .. "): " .. msg
    end)
    :totable()

  if #lines == 0 then
    vim.notify("No diagnostics found", vim.log.levels.INFO)
    return
  end

  M.send_text(table.concat(lines, "\n"))
end

---@return string range suffix or empty string
local function format_line_range()
  local mode = vim.fn.mode()
  if not mode:match("[vV]") then
    return ""
  end
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  local start_line = math.min(start_pos[2], end_pos[2])
  local end_line = math.max(start_pos[2], end_pos[2])
  return config.config.path_range_format:gsub("{start}", start_line):gsub("{end}", end_line)
end

-- Send the relative path of the current buffer
function M.send_rel_path()
  local range = format_line_range()
  local path = paths.get_relative_path()
  select_pane(function(pane_id)
    send_to_pane(M.config.path_prefix .. path .. range .. M.config.path_suffix, pane_id)
  end)
end

-- Send the absolute path of the current buffer
function M.send_abs_path()
  local range = format_line_range()
  local abs_path = vim.api.nvim_buf_get_name(0)
  select_pane(function(pane_id)
    send_to_pane(M.config.path_prefix .. abs_path .. range .. M.config.path_suffix, pane_id)
  end)
end

-- Send the current selection
function M.send_selection()
  -- capture positions and mode while still in visual mode
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  local mode = vim.fn.mode()
  local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
  local text = M._surround_selection(lines)
  M.send_text(text)
end

function M.reset_pane()
  if vim.g.sendit_pane then
    vim.g.sendit_pane = nil
    vim.notify("Sendit: pane selection cleared")
  else
    vim.notify("Sendit: no pane was set", vim.log.levels.INFO)
  end
end

---@param text string
function M.send_text(text)
  select_pane(function(pane_id)
    send_to_pane(text, pane_id)
  end)
end

return M
