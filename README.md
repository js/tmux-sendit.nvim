# tmux-sendit.nvim

Send selected buffer contents or file paths to another tmux pane without leaving neovim.

Select code or a file path, pick a target pane, and the content is inserted as if you typed it. Useful for feeding code snippets, file references, or context to a CLI tool running in another pane - like sending selections to a claude code session without constantly switching between tmux panes.

<img width="1670" height="899" alt="image" src="https://github.com/user-attachments/assets/5976a263-0b48-4a6e-9c36-784fb8080cad" />

<img width="1670" height="899" alt="image" src="https://github.com/user-attachments/assets/b0d932c9-7167-499c-a4f5-6010458181fd" />

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

  -- only list panes from the current tmux session in the picker
  only_current_session = true,

  -- prefix/suffix wrapped around selections sent to the pane
  selection_prefix = "\n```",
  selection_suffix = "```\n",

  -- prefix/suffix wrapped around file paths sent to the pane
  path_prefix = "@",
  path_suffix = " ",
})
````

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
  },
  opts = {},
}
```

#### Commands

| command / key        | mode   | description                         |
| -------------------- | ------ | ----------------------------------- |
| `:Sendit selection`  | visual | send the current visual selection   |
| `:Sendit path`       | normal | send the project-relative file path |
| `:Sendit fullpath`   | normal | send the absolute file path         |
| `:Sendit diagnostic` | normal | send diagnostics to tmux pane       |

## License

MIT
