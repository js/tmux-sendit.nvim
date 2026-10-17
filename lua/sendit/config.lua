---@class sendit.ConfigModule
---@field config sendit.Config
---@field setup fun(opts?: sendit.Config)
local M = {}

---@class sendit.Config
---@field backend "auto"|"tmux"|"rex" Where targets live; "auto" prefers tmux, then the Rex block running Neovim
---@field cmd? string[] tmux only: custom command, run with the pane id and text appended; nil sends literal text with tmux send-keys
---@field pane_scope "window"|"session"|"all" Scope for listing panes or Rex blocks in the picker
---@field focus_after_send boolean Focus the destination pane after sending
---@field remember_last boolean Remember and reuse last used pane until `:Sendit reset`
---@field selection_prefix string Prefix for the selection sent to the tmux pane
---@field selection_suffix string Suffix for the selection sent to the tmux pane
---@field path_prefix string Prefix for paths sent to the tmux pane
---@field path_suffix string Suffix for paths sent to the tmux pane
---@field path_range_format string Format for line range appended to paths in visual mode ({start} and {end} are replaced)
---@field process_filter (fun(): table[]?)|false Returns the target list for the picker; false shows every target in scope
local defaults = {
  backend = "auto", -- "auto" (tmux if $TMUX is set, else Rex), "tmux" or "rex"
  pane_scope = "session", -- "window" (current window), "session" (current session), "all" (all sessions)
  focus_after_send = true, -- focus the destination pane after sending
  -- remember and reuse last used pane, will always send to this pane until `:Sendit reset`
  remember_last = true,

  -- prefix/suffix for the selection that gets sent to the tmux pane
  selection_prefix = "\n```",
  selection_suffix = "```\n",

  -- prefix/suffix for paths that gets sent to the tmux pane
  path_prefix = "@",
  path_suffix = " ",

  -- format for line range appended to paths in visual mode ({start} and {end} are replaced)
  path_range_format = "#L{start}-L{end}",

  -- function returning the target list for the picker, or false to show every target in scope.
  -- The default restricts the picker to targets running known coding-agent processes.
  process_filter = function()
    return require("sendit.processes").filter({
      "claude",
      "codex",
      "opencode",
      "gemini",
      "copilot",
      "pi",
    })
  end,
}

---@type sendit.Config
M.config = defaults

---@param opts? sendit.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
