# tmux-sendit.nvim

Send selected buffer contents, file paths, or diagnostics to another tmux pane without leaving neovim.

Select code, a file path, or diagnostics, pick a target pane, and the content is inserted as if you typed it. Useful for feeding code snippets, file references, diagnostics, or context to a CLI tool running in another pane - like sending selections to a claude code session without constantly switching between tmux panes.

<img width="1653" height="1092" alt="Prompt selection" src="https://github.com/user-attachments/assets/73d088e2-6342-4c77-bcd7-100617e05a4a" />
<img width="1653" height="1092" alt="Target pane and agent selection" src="https://github.com/user-attachments/assets/9bd024ee-8640-40f9-a7ab-201b0a98bc7f" />
<img width="1670" height="899" alt="Context inserted" src="https://github.com/user-attachments/assets/b0d932c9-7167-499c-a4f5-6010458181fd" />

## Requirements

- neovim >= 0.9
- tmux

## Installation

### lazy.nvim

```lua
{
  "js/tmux-sendit.nvim",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "js/tmux-sendit.nvim",
  config = function()
    require("sendit").setup({})
  end,
}
```

### mini.deps

```lua
MiniDeps.add({
  source = "js/tmux-sendit.nvim",
})
require("sendit").setup({})
```

## Configuration

These are the defaults — pass any overrides to `setup()`:

````lua
require("sendit").setup({
  -- shell command used to send text to a tmux pane
  cmd = { "tmux", "send-keys", "-t" },

  -- scope for listing tmux panes: "window" (current window) | "session" (current session) | "all" (all sessions)
  pane_scope = "session",

  -- focus the destination pane after sending
  focus_after_send = true,

  -- remember and reuse last used pane, will always send to this pane until `:Sendit reset`
  remember_last = true,

  -- prefix/suffix wrapped around selections sent to the pane
  selection_prefix = "\n```",
  selection_suffix = "```\n",

  -- prefix/suffix wrapped around file paths sent to the pane
  path_prefix = "@",
  path_suffix = " ",

  -- format for line range appended to paths in visual mode
  path_range_format = "#L{start}-L{end}",

  -- function returning the pane list for the picker, or nil to show every pane in scope.
  -- The default restricts the picker to panes running known coding-agent processes
  -- (claude, codex, opencode, gemini, copilot, pi).
  process_filter = function()
    return require("sendit.processes").filter({
      "claude", "codex", "opencode", "gemini", "copilot", "pi",
    })
  end,
})
````

### Filtering the pane picker

By default the picker only lists tmux panes whose process tree contains a known
coding-agent CLI. The list is matched against a small built-in registry that
walks each pane's process descendants (so node/python-wrapped CLIs like
`claude` or `codex` are detected even when the foreground process reports as
`node`). Built-in names: `claude`, `codex`, `opencode`, `gemini`, `copilot`
(excluding `copilot-language-server`), and `pi`.

To narrow or extend the set, pass a different name list:

```lua
process_filter = function()
  return require("sendit.sessions").filter({ "claude", "codex" })
end,
```

To disable filtering entirely and show every pane in scope:

```lua
process_filter = nil,
```

For fully custom logic, supply your own function returning a list of pane
tables (`{ tmux_id, id, command, agent? }`).

## Commands & Keybindings

No keybindings are set by default. Bind the functions you need in your config:

```lua
-- lazy.nvim example with keybindings
{
  "js/tmux-sendit.nvim",
  keys = {
    { "<leader>a", group = "sendit", icon = "", desc = "sendit to tmux" },
    { "<leader>as", function() require("sendit").send_selection() end, mode = "v", desc = "Send selection to tmux pane" },
    { "<leader>af", function() require("sendit").send_rel_path() end, mode = { "n", "v" }, desc = "Send relative file path to tmux pane" },
    { "<leader>aF", function() require("sendit").send_abs_path() end, mode = { "n", "v" }, desc = "Send absolute file path to tmux pane" },
    { "<leader>ad", function() require("sendit").send_diagnostic() end, mode = { "n", "v" }, desc = "Send diagnostics to tmux pane" },
    { "<leader>ap", function() require("sendit.prompt").select_prompt() end, mode = { "n", "v" }, desc = "Select Prompt Template…" },
  },
  opts = {},
}
```

#### Commands

| command / key        | mode   | description                                                          |
| -------------------- | ------ | -------------------------------------------------------------------- |
| `:Sendit selection`  | visual | send the current visual selection                                    |
| `:Sendit path`       | n / v  | send the project-relative file path (with line range in visual mode) |
| `:Sendit fullpath`   | n / v  | send the absolute file path (with line range in visual mode)         |
| `:Sendit diagnostic` | normal | send diagnostics to tmux pane                                        |
| `:Sendit prompt`     | n / v  | select among prompt templates                                        |
| `:Sendit reset`      | normal | clear the remembered target pane                                     |

## Pane Selection

The pane picker automatically filters out the pane running neovim. When only one target pane is available, it sends directly without prompting. After selecting a pane, it's remembered for subsequent sends — use `:Sendit reset` to clear it.

## License

MIT
