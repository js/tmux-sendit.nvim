local M = {}

---@type sendit.PathsModule
local paths = require("sendit.paths")
---@type sendit.TmuxModule
local tmux = require("sendit.tmux")
---@type sendit.ConfigModule
local config = require("sendit.config")
local prompt = require("sendit.prompt")
---@type sendit.DiagnosticsModule
local diagnostics = require("sendit.diagnostics")

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
    prompt = prompt.select_prompt,
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
  ---@type vim.Diagnostic[]
  local diags

  if mode:match("[vV]") then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    -- handle whether if selecting up or down, getpos returns [bufnum, lnum, col, off]
    local start_line = math.min(start_pos[2], end_pos[2]) - 1
    local end_line = math.max(start_pos[2], end_pos[2]) - 1
    local all_diags = vim.diagnostic.get(0)

    diags = vim.tbl_filter(
      ---@param d vim.Diagnostic
      function(d)
        return d.lnum <= end_line and (d.end_lnum or d.lnum) >= start_line
      end,
      all_diags
    ) --[[@as vim.Diagnostic[] ]]
  else
    local cursor = vim.api.nvim_win_get_cursor(0)
    diags = vim.diagnostic.get(0, { lnum = cursor[1] - 1 })
  end

  local rel_path = paths.get_relative_path()

  local lines = vim
    .iter(diags)
    :map(function(d)
      return diagnostics.format(d, rel_path)
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
  local range = config.config.path_range_format:gsub("{start}", start_line):gsub("{end}", end_line)
  return range
end

-- Send the relative path of the current buffer
function M.send_rel_path()
  local range = format_line_range()
  local path = paths.get_relative_path()
  tmux.select_pane(function(pane_id)
    tmux.send_to_pane(M.config.path_prefix .. path .. range .. M.config.path_suffix, pane_id)
  end)
end

-- Send the absolute path of the current buffer
function M.send_abs_path()
  local range = format_line_range()
  local abs_path = vim.api.nvim_buf_get_name(0)
  tmux.select_pane(function(pane_id)
    tmux.send_to_pane(M.config.path_prefix .. abs_path .. range .. M.config.path_suffix, pane_id)
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
  tmux.select_pane(function(pane_id)
    tmux.send_to_pane(text, pane_id)
  end)
end

return M
