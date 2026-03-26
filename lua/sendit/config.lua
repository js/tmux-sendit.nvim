local M = {}

---@class sendit.Config
---@field cmd string[] Shell command to run on selected text
---@field pane_scope "window"|"session"|"all" Scope for listing tmux panes in the picker
local defaults = {
  cmd = { "tmux", "send-keys", "-t" },
  pane_scope = "session", -- "window" (current window), "session" (current session), "all" (all sessions)

  -- prefix/suffix for the selection that gets sent to the tmux pane
  selection_prefix = "\n```",
  selection_suffix = "```\n",

  -- prefix/suffix for paths that gets sent to the tmux pane
  path_prefix = "@",
  path_suffix = " ",
}

---@type sendit.Config
M.config = defaults

---@param opts? sendit.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
