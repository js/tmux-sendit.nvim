local M = {}

---@type sendit.TmuxModule
local tmux = require("sendit.tmux")
---@type sendit.PathsModule
local paths = require("sendit.paths")
---@type sendit.DiagnosticsModule
local diagnostics = require("sendit.diagnostics")

-- TODO: put in config
local prompts = {
  -- Replacements: {file} {line} {diagnostic} {selection}
  -- TODO: treesitter {function} ?
  "Look at the uncomitted changes for any obvious bugs, mistakes or things that could be improved or simplified",
  "Add documentation to this function {file}:{line}",
  "Fix this issue: {diagnostic}",
  "Review {file} for any issues or if it could be improved or simplified",
  "Explain this: {selection}",
  "Document this function {file}:{line}",
  "Write a short comment about what's going on here {file}:{line}",
  "{diagnostic}",
  "in {file}:{line} ",
}

---@class sendit.PromptContext
---@field file string
---@field line integer
---@field selection string
---@field diagnostic string

---@return sendit.PromptContext
local function capture_context()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  local selection = ""
  local mode = vim.fn.mode()
  if mode:match("[vV]") then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
    selection = table.concat(lines, "\n")
  end

  local rel_path = paths.get_relative_path()
  local diags = vim.diagnostic.get(0, { lnum = line - 1 })
  local diag_lines = vim
    .iter(diags)
    :map(function(d)
      return diagnostics.format(d, rel_path)
    end)
    :totable()

  return {
    file = rel_path,
    line = line,
    selection = selection,
    diagnostic = table.concat(diag_lines, "\n"),
  }
end

---@param template string
---@param ctx sendit.PromptContext
---@return string
local function substitute(template, ctx)
  local out = template
    :gsub("{file}", ctx.file)
    :gsub("{line}", tostring(ctx.line))
    :gsub("{selection}", ctx.selection)
    :gsub("{diagnostic}", ctx.diagnostic)
  return out
end

---@param template string
---@param ctx sendit.PromptContext
local function prompt_selected(template, ctx)
  local text = substitute(template, ctx)
  tmux.select_pane(function(pane_id)
    tmux.send_to_pane(text, pane_id)
  end)
end

function M.select_prompt()
  local ctx = capture_context()
  vim.ui.select(prompts, {
    prompt = "Select prompt template",
    preview = true,
    format_item = function(p)
      return p
    end,
  }, function(choice)
    if choice then
      prompt_selected(choice, ctx)
    end
  end)
end

return M
