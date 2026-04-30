local M = {}

---@class sendit.Config
---@field cmd string[] Shell command to run on selected text
---@field pane_scope "window"|"session"|"all" Scope for listing tmux panes in the picker
---@field process_filter? fun(): table[] Returns the pane list for the picker; nil disables filtering
local defaults = {
  cmd = { "tmux", "send-keys", "-t" },
  pane_scope = "session", -- "window" (current window), "session" (current session), "all" (all sessions)
  focus_after_send = true, -- focus the destination pane after sending

  -- prefix/suffix for the selection that gets sent to the tmux pane
  selection_prefix = "\n```",
  selection_suffix = "```\n",

  -- prefix/suffix for paths that gets sent to the tmux pane
  path_prefix = "@",
  path_suffix = " ",

  -- format for line range appended to paths in visual mode ({start} and {end} are replaced)
  path_range_format = "#L{start}-L{end}",

  -- function returning the pane list for the picker, or nil to show every pane in scope.
  -- The default restricts the picker to panes running known coding-agent processes.
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
