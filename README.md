# tmux-sendit.nvim

Send selected buffer contents, file paths, or diagnostics to another tmux pane or Rex block without leaving neovim.

Select code, a file path, or diagnostics, pick a target pane, and the content is inserted as if you typed it. Useful for feeding code snippets, file references, diagnostics, or context to a CLI tool running in another pane - like sending selections to a claude code session without constantly switching between tmux panes.

<img width="1653" height="1092" alt="Prompt selection" src="https://github.com/user-attachments/assets/73d088e2-6342-4c77-bcd7-100617e05a4a" />
<img width="1653" height="1092" alt="Target pane and agent selection" src="https://github.com/user-attachments/assets/9bd024ee-8640-40f9-a7ab-201b0a98bc7f" />
<img width="1670" height="899" alt="Context inserted" src="https://github.com/user-attachments/assets/b0d932c9-7167-499c-a4f5-6010458181fd" />

## Requirements

- neovim >= 0.10
- tmux, or the `rex` CLI when Neovim runs inside a Rex block

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

Pass overrides to `setup()`. These are the defaults:

````lua
require("sendit").setup({
  -- where targets live: "auto" (tmux when $TMUX is set, else Rex) | "tmux" | "rex"
  backend = "auto",

  -- tmux only: custom command run with the pane id and the text appended.
  -- Unset by default, which sends the text literally with
  -- `tmux send-keys -l -t <pane> -- <text>`.
  -- cmd = { "tmux", "send-keys", "-t" },

  -- scope for listing panes or Rex blocks: "window" (current window) | "session" (current session) | "all" (all sessions)
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

  -- function returning the target list for the picker, or false to show every target in scope.
  -- The default restricts the picker to targets running known coding-agent processes
  -- (claude, codex, opencode, gemini, copilot, pi).
  process_filter = function()
    return require("sendit.processes").filter({
      "claude", "codex", "opencode", "gemini", "copilot", "pi",
    })
  end,
})
````

### Choosing tmux or Rex

With `backend = "auto"`, sendit uses tmux when `$TMUX` is set. Otherwise it
uses Rex when both `$REX_SESSION` and `$REX_BLOCK` are set. If neither is set,
sendit shows an error and sends nothing.

Set `backend = "tmux"` or `backend = "rex"` to pick one explicitly, for
example to reach Rex blocks from a tmux session that runs inside a Rex block.
The chosen backend still needs its variables.

Tmux window and session scopes use Neovim's `$TMUX_PANE`, not the active tab.
With `focus_after_send`, tmux runs `select-pane`. This changes the active pane
within the target window but does not switch a client's active window or session.

For Rex, `pane_scope` works like this:

- `"window"` lists the blocks in the window that holds Neovim's own block.
  The window that has focus in the Rex app does not matter.
- `"session"` lists the blocks in `$REX_SESSION`.
- `"all"` lists the blocks of every session from `rex ls`.

sendit runs `rex send -s SESSION -b BLOCK -- TEXT`, so the text arrives
exactly as written and sendit never presses Return. `cmd` does not apply to
Rex. With `focus_after_send`, sendit runs `rex focus -s SESSION BLOCK`. That
command makes the block the focused block of its Rex session. It does not ask
the Rex app to show that session, so after a send to another session the app
can stay on the session it already shows.

### Filtering the pane picker

By default the picker only lists targets that run a known coding-agent CLI.
For tmux, each pane's `#{pane_tty}` is matched against
`ps -axo tty=,command=` output, so node/python-wrapped CLIs like `claude` or
`codex` are detected even when the foreground process reports as `node`.
For Rex, sendit reads the block's process with
`rex block call -s SESSION -b BLOCK process` and matches only the `name`,
`argv0`, `path`, `invoked_path`, and `script` fields that Rex reports. It sees
no full argv. A wrapper that hides the agent's name from all of those fields
is not detected.
Built-in names: `claude`, `codex`, `opencode`, `gemini`, `copilot` (excluding
`copilot-language-server`), and `pi`.

To narrow or extend the set, pass a different name list:

```lua
process_filter = function()
  return require("sendit.processes").filter({ "claude", "codex" })
end,
```

To disable filtering entirely and show every target in scope, use `false`.
`nil` does not work, because `setup()` keeps the default for `nil` values.

```lua
process_filter = false,
```

For fully custom logic, supply your own function that returns the list of
targets for the picker. The picker labels each entry with `agent` or
`command`. sendit ignores entries that do not fit the active backend, with a
warning.

- tmux entries are `{ tmux_id, id, command, pane_tty, agent }`. `id` is
  required. sendit sends to `tmux_id` when it is present and to `id`
  otherwise. A custom `cmd` always receives `id`. Your function owns the whole
  list, so leave out the pane running Neovim yourself.
  `require("sendit.processes").filter()` already does this.
- Rex entries are `{ session, block_id, id, command, agent }`. `session` and
  `block_id` must be full Rex IDs, not labels or suffixes. sendit removes
  Neovim's own block from the list.

A function that returns something other than a list makes sendit show an
error and send nothing.

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
| `:Sendit reset`      | normal | clear the remembered target                                          |

## Prompt Templates

`:Sendit prompt` (or `require("sendit.prompt").select_prompt()`) opens a
`vim.ui.select` picker over a small built-in list of prompt templates aimed at
coding agents. The chosen template is expanded against the current buffer
context and sent to the target pane.

Supported placeholders:

| placeholder    | replaced with                                                                   |
| -------------- | ------------------------------------------------------------------------------- |
| `{file}`       | project-relative path of the current buffer                                     |
| `{line}`       | current cursor line (1-based)                                                   |
| `{selection}`  | visual selection text (empty in normal mode)                                    |
| `{diagnostic}` | diagnostics on the current line (or empty if none)                              |

The template list itself is not yet user-configurable.

## Pane Selection

The built-in lists leave out the pane or block running Neovim. When only one target is available, sendit sends to it without asking. With `remember_last`, sendit remembers the chosen target and reuses it while that target still exists. Use `:Sendit reset` to clear it.

sendit remembers a tmux pane by its pane id, such as `%53`, and a Rex block by its session and block id. A target remembered under one backend is never used by the other.

## Running the tests

```sh
nvim --headless -u NONE -l tests/run.lua
```

The tests stub `vim.system`, so they never run tmux or rex.

Rex process discovery runs synchronously, once per block, with a five-second
command timeout. All-session filtering can pause Neovim while those calls finish.

## License

MIT
