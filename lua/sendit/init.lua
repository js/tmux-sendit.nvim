local M = {}

local paths = require("sendit.paths")
local tmux = require("sendit.tmux")

---@class sendit.Config
---@field cmd string[] Shell command to run on selected text
local defaults = {
  cmd = { "tmux", "send-keys", "-t" },
  only_current_session = true, -- should only panes from the current session be listed in the picker

  -- prefix/suffix for the selection that gets sent to the tmux pane
  selection_prefix = "```\n",
  selection_suffix = "\n```\n",

  -- prefix/suffix for paths that gets sent to the tmux pane
  path_prefix = "@",
  path_suffix = " ",
}

---@type sendit.Config
M.config = defaults

---@param opts? sendit.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  local subcommands = {
    selection = M.send_selection,
    path = M.send_rel_path,
    fullpath = M.send_abs_path,
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
        M.send_text(lines)
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

---@param on_select fun(pane_id: string)
local function select_pane(on_select)
  local all_panes = vim.fn.systemlist(tmux.list_command())
  local panes = vim
    .iter(all_panes)
    :map(function(pane)
      local id, rest = pane:match("^(%S+)%s(.+)$")
      return { id = id, command = rest }
    end)
    :totable()
  -- TODO: try telescope -> snacks -> vim.ui.select
  vim.ui.select(panes, {
    prompt = "Select target tmux pane:",
    format_item = function(pane)
      return pane.id .. " " .. pane.command
    end,
  }, function(choice)
    if choice then
      on_select(choice.id)
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
      vim.notify("Sent to pane '" .. pane_id .. "'")
    end
  end)
end

function M.send_rel_path()
  local path = paths.get_relative_path()
  select_pane(function(pane_id)
    send_to_pane(M.config.path_prefix .. path, pane_id .. M.config.path_suffix)
  end)
end

function M.send_abs_path()
  local abs_path = vim.api.nvim_buf_get_name(0)
  select_pane(function(pane_id)
    send_to_pane(M.config.path_prefix .. abs_path .. M.config.path_suffix, pane_id)
  end)
end

function M.send_selection()
  -- capture positions and mode while still in visual mode
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  local mode = vim.fn.mode()
  local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })

  M.send_text(lines)
end

---@param lines string[]
function M.send_text(lines)
  local text = M.config.selection_prefix .. table.concat(lines, "\n") .. M.config.selection_suffix

  select_pane(function(pane_id)
    send_to_pane(text, pane_id)
  end)
end

return M
