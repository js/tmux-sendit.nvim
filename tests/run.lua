local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local json = vim.json.encode
local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR

local function block(id, window, label)
  return {
    block_id = id,
    label = label,
    creator_name = "com.superlogical.terminal",
    flavor = "com.superlogical.terminal.shell",
    host_id = "host:1",
    placement = "placed",
    window_id = window,
  }
end

local function process(fields)
  local p = vim.tbl_extend("force", { pid = 42, user_id = 501, user = "me", cwd = "/work" }, fields)
  return json({ last_exit = vim.NIL, child = p, foreground = p, home = "/Users/me" })
end

local shell = process({ name = "zsh", path = "/bin/zsh", invoked_path = "/bin/zsh", argv0 = "-zsh" })

-- Shapes copied from `rex ls --json`, `rex block ls -s S --json` and `rex block call ... process`.
local function rex_world()
  return {
    ["rex ls --json"] = json({
      sessions = {
        { session_id = "session:local", label = "local" },
        { session_id = "session:remote", label = "remote" },
      },
    }),
    ["rex block ls -s session:local --json"] = json({
      blocks = {
        block("block:editor", "window:1", "nvim"),
        block("block:same", "window:1", "shell"),
        block("block:tab", "window:2", "shell"),
        block("block:lsp", "window:2", "lsp"),
      },
    }),
    ["rex block ls -s session:remote --json"] = json({ blocks = { block("block:remote", "window:9", "shell") } }),
    ["rex block call -s session:local -b block:editor process"] = process({
      name = "nvim",
      argv0 = "nvim",
      path = "/opt/homebrew/bin/nvim",
    }),
    ["rex block call -s session:local -b block:same process"] = process({
      name = "node",
      path = "/opt/homebrew/Cellar/node/26.11.0/bin/node",
      invoked_path = "/opt/homebrew/bin/node",
      argv0 = "pi",
      script = "/tmp/receiver.js",
    }),
    ["rex block call -s session:local -b block:tab process"] = shell,
    ["rex block call -s session:local -b block:lsp process"] = process({
      name = "copilot",
      argv0 = "copilot",
      path = "/opt/homebrew/bin/node",
      script = "/lib/node_modules/@github/copilot-language-server/dist/main.js",
    }),
    ["rex block call -s session:remote -b block:remote process"] = process({
      name = "node",
      argv0 = "node",
      path = "/opt/homebrew/bin/node",
      script = "/lib/node_modules/@anthropic-ai/claude-code/cli.js",
    }),
  }
end

local PANE_FORMAT = "#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_tty} #{pane_current_command}"

local function tmux_world()
  return {
    ["tmux list-panes -s -t %0 -F " .. PANE_FORMAT] = table.concat({
      "%0 local:1.0 /dev/ttys001 nvim",
      "%1 local:1.1 /dev/ttys002 node",
      "%2 local:2.0 /dev/ttys003 zsh",
    }, "\n"),
    ["ps -axo tty=,command="] = "ttys001  nvim\nttys002  pi /tmp/receiver.js /tmp/out\nttys003  -zsh\n??       /sbin/launchd\n",
  }
end

local world, calls, notes, picks

vim.system = function(argv, _, on_exit)
  table.insert(calls, argv)
  local key = table.concat(argv, " ")
  local reply = world[key]
  local result
  if type(reply) == "function" then
    result = reply()
  elseif type(reply) == "table" then
    result = reply
  elseif reply then
    result = { code = 0, stdout = reply, stderr = "" }
  elseif
    argv[2] == "send"
    or argv[2] == "send-keys"
    or argv[2] == "focus"
    or argv[2] == "select-pane"
    or argv[1] == "mycmd"
  then
    result = { code = 0, stdout = "", stderr = "" }
  else
    result = { code = 1, stdout = "", stderr = "unexpected command: " .. key }
  end
  if on_exit then
    on_exit(result)
  end
  return {
    wait = function()
      return result
    end,
  }
end
vim.schedule = function(fn)
  fn()
end
vim.notify = function(msg, level)
  table.insert(notes, { msg = msg, level = level or INFO })
end
local pick
vim.ui.select = function(items, opts, cb)
  table.insert(picks, { items = items, opts = opts })
  cb(pick(items, opts))
end

local sendit = require("sendit")
local prompt = require("sendit.prompt")

local function setup(env, opts, w)
  for _, var in ipairs({ "TMUX", "TMUX_PANE", "REX_SESSION", "REX_BLOCK" }) do
    vim.env[var] = env[var]
  end
  world, calls, notes, picks = w or {}, {}, {}, {}
  vim.g.sendit_target, vim.g.sendit_pane = nil, nil
  pick = function(items)
    return items[1]
  end
  sendit.setup(vim.tbl_extend("force", { focus_after_send = false }, opts or {}))
end

local REX = { REX_SESSION = "session:local", REX_BLOCK = "block:editor" }
local TMUX = { TMUX = "/tmp/tmux-501/default,1,0", TMUX_PANE = "%0" }
local BOTH = vim.tbl_extend("force", REX, TMUX)

local function sends()
  return vim.tbl_filter(function(argv)
    return argv[2] == "send" or argv[2] == "send-keys" or argv[1] == "mycmd"
  end, calls)
end

local function ran(prefix)
  return vim.iter(calls):any(function(argv)
    return table.concat(argv, " "):find(prefix, 1, true) == 1
  end)
end

local function notes_at(level)
  return vim.tbl_filter(function(n)
    return n.level == level
  end, notes)
end

local function eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual:   %s"):format(what or "", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function ok(cond, what)
  if not cond then
    error(what .. "\ncalls: " .. vim.inspect(calls) .. "\nnotes: " .. vim.inspect(notes), 2)
  end
end

local function only_send(expected)
  eq(sends(), { expected }, "exactly one send")
end

local function rex_send(block_id, text, session)
  return { "rex", "send", "-s", session or "session:local", "-b", block_id, "--", text }
end

local function tmux_send(target, text)
  return { "tmux", "send-keys", "-l", "-t", target, "--", text }
end

local function errors_with(text)
  local errs = notes_at(ERROR)
  ok(#errs == 1 and errs[1].msg:find(text, 1, true), "one ERROR mentioning " .. text)
  eq(sends(), {}, "nothing sent")
  eq(picks, {}, "no picker")
end

local tests = {}
local function test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local payload = "-n $(touch /tmp/x); `echo nope` \"q\" 'q' \\ Enter æ\nsecond line\n"

test("auto prefers tmux when both tmux and rex env are set", function()
  setup(BOTH, { process_filter = false }, vim.tbl_extend("force", tmux_world(), rex_world()))
  sendit.send_text("hi")
  ok(ran("tmux list-panes") and not ran("rex"), "listed tmux only")
end)

test("auto uses rex without tmux", function()
  setup(REX, { process_filter = false, pane_scope = "window" }, rex_world())
  sendit.send_text("hi")
  only_send(rex_send("block:same", "hi"))
end)

test("explicit rex inside tmux reaches rex", function()
  setup(BOTH, { backend = "rex", process_filter = false, pane_scope = "window" }, rex_world())
  sendit.send_text("hi")
  only_send(rex_send("block:same", "hi"))
  ok(not ran("tmux"), "no tmux command")
end)

test("explicit tmux without $TMUX errors", function()
  setup(REX, { backend = "tmux" }, rex_world())
  sendit.send_text("hi")
  errors_with("needs $TMUX")
  eq(calls, {}, "no commands")
end)

test("explicit rex without both rex variables errors", function()
  setup({ REX_SESSION = "session:local", TMUX = TMUX.TMUX }, { backend = "rex" }, rex_world())
  sendit.send_text("hi")
  errors_with("needs $REX_SESSION and $REX_BLOCK")
  eq(calls, {}, "no commands, no fallback session")
end)

test("auto with no context errors without picking a session", function()
  setup({}, {}, rex_world())
  sendit.send_text("hi")
  errors_with("not inside tmux")
  eq(calls, {}, "no commands")
end)

test("invalid backend errors", function()
  setup(BOTH, { backend = "wezterm" })
  sendit.send_text("hi")
  errors_with("invalid backend 'wezterm'")
end)

test("rex sends literal text with -- and no Enter", function()
  setup(REX, { process_filter = false, pane_scope = "window" }, rex_world())
  sendit.send_text(payload)
  only_send(rex_send("block:same", payload))
  ok(not ran("rex send-key"), "no send-key")
end)

test("tmux default sends literal text to the pane id with -l and --", function()
  setup(TMUX, { process_filter = false }, tmux_world())
  pick = function(items)
    return items[1]
  end
  sendit.send_text(payload)
  only_send(tmux_send("%1", payload))
end)

test("custom tmux cmd keeps the legacy argv and display id", function()
  setup(TMUX, { process_filter = false, cmd = { "mycmd", "-t" } }, tmux_world())
  sendit.send_text("hi")
  only_send({ "mycmd", "-t", "local:1.1", "hi" })
end)

test("custom cmd does not apply to rex", function()
  setup(REX, { process_filter = false, pane_scope = "window", cmd = { "mycmd", "-t" } }, rex_world())
  sendit.send_text("hi")
  only_send(rex_send("block:same", "hi"))
end)

test("focus after send runs rex focus for the sent block", function()
  setup(REX, { process_filter = false, pane_scope = "window", focus_after_send = true }, rex_world())
  sendit.send_text("hi")
  eq(calls[#calls], { "rex", "focus", "-s", "session:local", "block:same" }, "focus last")
end)

test("failed send reports stderr and skips focus", function()
  local w = rex_world()
  w["rex send -s session:local -b block:same -- hi"] = { code = 1, stdout = "", stderr = "block gone" }
  setup(REX, { process_filter = false, pane_scope = "window", focus_after_send = true }, w)
  sendit.send_text("hi")
  ok(#notes_at(ERROR) == 1 and notes_at(ERROR)[1].msg:find("block gone", 1, true), "ERROR with stderr")
  ok(not ran("rex focus"), "no focus")
end)

test("signal-terminated send errors without success or focus", function()
  local w = rex_world()
  w["rex send -s session:local -b block:same -- hi"] = { code = 0, signal = 15, stdout = "", stderr = "" }
  setup(REX, { process_filter = false, pane_scope = "window", focus_after_send = true }, w)
  sendit.send_text("hi")
  ok(#notes_at(ERROR) == 1 and notes_at(ERROR)[1].msg:find("signal 15", 1, true), "signal reported")
  eq(notes_at(INFO), {}, "no success")
  ok(not ran("rex focus"), "no focus")
end)

test("signal-terminated listing never sends despite usable stdout", function()
  local w = rex_world()
  w["rex block ls -s session:local --json"] = {
    code = 0,
    signal = 15,
    stdout = w["rex block ls -s session:local --json"],
    stderr = "",
  }
  setup(REX, { process_filter = false, pane_scope = "window" }, w)
  sendit.send_text("hi")
  errors_with("signal 15")
end)

for _, outcome in ipairs({
  { code = 1, stderr = "focus unavailable" },
  { code = 0, signal = 15, stderr = "" },
  function()
    error("cannot launch focus")
  end,
}) do
  test("failed focus warns without resending text", function()
    local w = rex_world()
    w["rex focus -s session:local block:same"] = outcome
    setup(REX, { process_filter = false, pane_scope = "window", focus_after_send = true }, w)
    sendit.send_text("hi")
    only_send(rex_send("block:same", "hi"))
    ok(#notes_at(WARN) == 1 and notes_at(WARN)[1].msg:find("text sent, but focus failed", 1, true), "focus warning")
    eq(#notes_at(INFO), 1, "send succeeded")
  end)
end

test("send launch errors are reported without focus", function()
  local w = rex_world()
  w["rex send -s session:local -b block:same -- hi"] = function()
    error("cannot launch rex")
  end
  setup(REX, { process_filter = false, pane_scope = "window", focus_after_send = true }, w)
  sendit.send_text("hi")
  ok(#notes_at(ERROR) == 1 and notes_at(ERROR)[1].msg:find("cannot launch rex", 1, true), "launch error")
  eq(notes_at(INFO), {}, "no success")
  ok(not ran("rex focus"), "no focus")
end)

local function picked_blocks()
  return vim.tbl_map(function(item)
    return item.session .. " " .. item.block_id
  end, picks[1].items)
end

test("rex window scope uses the editor block's window", function()
  setup(REX, { process_filter = false, pane_scope = "window" }, rex_world())
  sendit.send_text("hi")
  eq(picks, {}, "single target needs no picker")
  only_send(rex_send("block:same", "hi"))
  ok(not ran("rex session inspect") and not ran("rex ls"), "no UI-focus or session lookup")
end)

test("rex window scope errors when the editor block is missing", function()
  setup(
    { REX_SESSION = "session:local", REX_BLOCK = "block:gone" },
    { process_filter = false, pane_scope = "window" },
    rex_world()
  )
  sendit.send_text("hi")
  errors_with("editor block block:gone not found")
end)

test("rex session scope lists the editor's session without the editor", function()
  setup(REX, { process_filter = false, pane_scope = "session" }, rex_world())
  sendit.send_text("hi")
  eq(picked_blocks(), { "session:local block:same", "session:local block:tab", "session:local block:lsp" })
end)

test("rex all scope lists every session per session, never block ls -A", function()
  setup(REX, { process_filter = false, pane_scope = "all" }, rex_world())
  pick = function(items)
    return vim.iter(items):find(function(i)
      return i.block_id == "block:remote"
    end)
  end
  sendit.send_text("hi")
  eq(picked_blocks(), {
    "session:local block:same",
    "session:local block:tab",
    "session:local block:lsp",
    "session:remote block:remote",
  })
  only_send(rex_send("block:remote", "hi", "session:remote"))
  ok(not ran("rex block ls -A"), "no -A")
end)

test("default filter on rex finds node with argv0 pi and rejects copilot-language-server", function()
  setup(REX, { pane_scope = "session" }, rex_world())
  sendit.send_text("hi")
  eq(picks, {}, "only the pi block matches")
  only_send(rex_send("block:same", "hi"))
end)

test("default filter on rex finds claude through the node script path across sessions", function()
  setup(REX, { pane_scope = "all" }, rex_world())
  sendit.send_text("hi")
  eq(
    vim.tbl_map(function(i)
      return i.agent .. " " .. i.block_id
    end, picks[1].items),
    { "pi block:same", "claude block:remote" }
  )
end)

test("an unreadable rex process warns once and counts as no agent", function()
  local w = rex_world()
  w["rex block call -s session:local -b block:tab process"] = { code = 1, stdout = "", stderr = "no such method" }
  w["rex block call -s session:local -b block:lsp process"] = "not json"
  setup(REX, { pane_scope = "session" }, w)
  sendit.send_text("hi")
  eq(#notes_at(WARN), 1, "one WARN")
  only_send(rex_send("block:same", "hi"))
end)

test("default filter on tmux matches pi by tty and excludes the editor pane", function()
  setup(TMUX, {}, tmux_world())
  sendit.send_text("hi")
  eq(picks, {}, "only the pi pane matches")
  only_send(tmux_send("%1", "hi"))
end)

test("filter name list narrows matches", function()
  setup(REX, {
    pane_scope = "all",
    process_filter = function()
      return require("sendit.processes").filter({ "claude" })
    end,
  }, rex_world())
  sendit.send_text("hi")
  only_send(rex_send("block:remote", "hi", "session:remote"))
end)

test("tmux callback rows are the complete list, including the editor pane", function()
  setup(TMUX, {
    process_filter = function()
      return {
        { tmux_id = "%0", id = "local:1.0", command = "nvim" },
        { tmux_id = "%7", id = "x:1.1", command = "node", agent = "claude" },
      }
    end,
  })
  pick = function(items)
    return items[2]
  end
  sendit.send_text("hi")
  eq(#picks[1].items, 2, "editor pane kept")
  only_send(tmux_send("%7", "hi"))
end)

test("legacy id-only tmux rows send to the id", function()
  setup(TMUX, {
    process_filter = function()
      return { { id = "x:1.1", command = "zsh" } }
    end,
  })
  sendit.send_text("hi")
  only_send(tmux_send("x:1.1", "hi"))
end)

test("invalid callback rows are dropped with one WARN", function()
  setup(TMUX, {
    process_filter = function()
      return { "x:1.1", { command = "zsh" }, { id = "x:1.2", command = "zsh" } }
    end,
  })
  sendit.send_text("hi")
  eq(#notes_at(WARN), 1, "one WARN")
  only_send(tmux_send("x:1.2", "hi"))
end)

test("tmux rejects Rex callback identity even when its display id matches a tmux pane", function()
  setup(TMUX, {
    process_filter = function()
      return {
        { session = "session:local", block_id = "block:same", id = "local:1.1", command = "rex" },
        { id = "local:2.0", command = "tmux" },
      }
    end,
  })
  sendit.send_text("hi")
  only_send(tmux_send("local:2.0", "hi"))
  eq(#notes_at(WARN), 1, "foreign identity warned")
end)

test("rex callback rows need session and block_id and lose the editor block", function()
  setup(REX, {
    process_filter = function()
      return {
        { session = "session:local", block_id = "block:editor" },
        { tmux_id = "%1", id = "local:1.1" },
        { session = "session:remote", block_id = "block:remote", agent = "claude" },
      }
    end,
  })
  sendit.send_text("hi")
  eq(#notes_at(WARN), 1, "tmux row warned")
  only_send(rex_send("block:remote", "hi", "session:remote"))
end)

test("a failing callback errors without a picker", function()
  setup(TMUX, {
    process_filter = function()
      error("callback broke", 0)
    end,
  })
  sendit.send_text("hi")
  errors_with("callback broke")
end)

test("remembered target is reused until reset", function()
  setup(REX, { process_filter = false, pane_scope = "session" }, rex_world())
  pick = function(items)
    return items[2]
  end
  sendit.send_text("one")
  sendit.send_text("two")
  eq(#picks, 1, "picker once")
  eq(sends(), { rex_send("block:tab", "one"), rex_send("block:tab", "two") })
  sendit.reset_pane()
  sendit.send_text("three")
  eq(#picks, 2, "picker after reset")
end)

test("remember_last = false asks every time, even with a remembered target", function()
  setup(REX, { process_filter = false, pane_scope = "session", remember_last = false }, rex_world())
  vim.g.sendit_target = { backend = "rex", key = "session:local\nblock:tab" }
  sendit.send_text("one")
  sendit.send_text("two")
  eq(#picks, 2, "picker twice")
end)

test("tmux window scope anchors on the editor pane, not the active window", function()
  local w = tmux_world()
  w["tmux list-panes -F " .. PANE_FORMAT] = "%2 local:2.0 /dev/ttys003 zsh\n%3 local:2.1 /dev/ttys004 zsh"
  w["tmux list-panes -t %0 -F " .. PANE_FORMAT] = "%0 local:1.0 /dev/ttys001 nvim\n%1 local:1.1 /dev/ttys002 node"
  setup(TMUX, { process_filter = false, pane_scope = "window" }, w)
  sendit.send_text("hi")
  eq(picks, {}, "single same-window pane")
  only_send(tmux_send("%1", "hi"))
end)

test("remembered tmux pane follows its stable pane id across renumbering", function()
  setup(TMUX, { process_filter = false }, tmux_world())
  pick = function(items)
    return items[2]
  end
  sendit.send_text("one")
  world["tmux list-panes -s -t %0 -F " .. PANE_FORMAT] =
    "%0 local:1.0 /dev/ttys001 nvim\n%5 local:1.1 /dev/ttys009 zsh\n%2 local:1.2 /dev/ttys003 zsh"
  sendit.send_text("two")
  eq(#picks, 1, "no second picker")
  eq(sends(), { tmux_send("%2", "one"), tmux_send("%2", "two") })
end)

test("a vanished remembered target is cleared and the picker opens", function()
  setup(REX, { process_filter = false, pane_scope = "session" }, rex_world())
  vim.g.sendit_target = { backend = "rex", key = "session:local\nblock:closed" }
  sendit.send_text("hi")
  eq(#picks, 1, "picker opened")
  eq(vim.g.sendit_target.key, "session:local\nblock:same", "replaced by the new pick")
end)

test("remembered targets do not cross backends even when keys match", function()
  setup(REX, { process_filter = false, pane_scope = "session" }, rex_world())
  local saved = { backend = "tmux", key = "session:local\nblock:same" }
  vim.g.sendit_target = saved
  vim.g.sendit_pane = "shell #same"
  pick = function()
    return nil
  end
  sendit.send_text("hi")
  eq(#picks, 1, "tmux memory ignored on rex")
  eq(sends(), {}, "cancel does not send")
  eq(vim.g.sendit_target, saved, "tmux memory kept")
  eq(vim.g.sendit_pane, "shell #same", "legacy memory kept")

  setup(TMUX, { process_filter = false }, tmux_world())
  saved = { backend = "rex", key = "%1" }
  vim.g.sendit_target = saved
  pick = function()
    return nil
  end
  sendit.send_text("hi")
  eq(#picks, 1, "rex memory ignored on tmux")
  eq(sends(), {}, "cancel does not send")
  eq(vim.g.sendit_target, saved, "rex memory kept")
end)

test("legacy vim.g.sendit_pane is honoured for tmux and migrated", function()
  setup(TMUX, { process_filter = false }, tmux_world())
  vim.g.sendit_pane = "local:2.0"
  sendit.send_text("hi")
  eq(picks, {}, "no picker")
  only_send(tmux_send("%2", "hi"))
  eq(vim.g.sendit_target, { backend = "tmux", key = "%2" })
  eq(vim.g.sendit_pane, nil)
end)

test("malformed block ls JSON errors instead of reporting no targets", function()
  local w = rex_world()
  w["rex block ls -s session:local --json"] = "{not json"
  setup(REX, { process_filter = false }, w)
  vim.g.sendit_target = { backend = "rex", key = "session:local\nblock:same" }
  sendit.send_text("hi")
  errors_with("invalid JSON")
  ok(vim.g.sendit_target ~= nil, "memory kept")
end)

for _, case in ipairs({
  { "a non-table block row", "session:local", json({ blocks = { false } }) },
  { "blocks that are not a list", "session:local", json({ blocks = "none" }) },
  { "a block without block_id", "session:local", json({ blocks = { { label = "shell" } } }) },
  { "a non-string block label", "session:local", json({ blocks = { block("block:x", "window:1", 7) } }) },
  { "a non-table session row", "sessions", json({ sessions = { "session:local" } }) },
  { "a session without session_id", "sessions", json({ sessions = { { label = "local" } } }) },
}) do
  test("rex list errors on " .. case[1], function()
    local w = rex_world()
    if case[2] == "sessions" then
      w["rex ls --json"] = case[3]
    else
      w["rex block ls -s " .. case[2] .. " --json"] = case[3]
    end
    setup(REX, { process_filter = false, pane_scope = "all" }, w)
    sendit.send_text("hi")
    errors_with("malformed")
  end)
end

for _, result in ipairs({ "x:1.1", { a = { id = "x:1.1" } } }) do
  test("a process_filter returning " .. vim.inspect(result):gsub("%s+", " ") .. " errors", function()
    setup(TMUX, {
      process_filter = function()
        return result
      end,
    })
    sendit.send_text("hi")
    errors_with("process_filter must return a list of targets")
  end)
end

test("failing rex ls reports stderr", function()
  local w = rex_world()
  w["rex ls --json"] = { code = 2, stdout = "", stderr = "server not running" }
  setup(REX, { pane_scope = "all" }, w)
  sendit.send_text("hi")
  errors_with("server not running")
end)

test("malformed tmux list-panes output errors without sending", function()
  local w = tmux_world()
  w["tmux list-panes -s -t %0 -F " .. PANE_FORMAT] = "unexpected backend output"
  setup(TMUX, { process_filter = false }, w)
  sendit.send_text("hi")
  errors_with("malformed pane list")
end)

test("failing tmux list-panes reports stderr", function()
  setup(TMUX, {}, { ["ps -axo tty=,command="] = "" })
  sendit.send_text("hi")
  errors_with("unexpected command: tmux list-panes")
end)

local function on_buffer()
  vim.cmd("enew! | silent! bwipeout! #")
  vim.api.nvim_buf_set_name(0, root .. "/lua/sendit/fixture.lua")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function rex_window()
  setup(REX, { process_filter = false, pane_scope = "window" }, rex_world())
  on_buffer()
end

test("send_rel_path and send_abs_path", function()
  rex_window()
  sendit.send_rel_path()
  sendit.send_abs_path()
  eq(sends(), {
    rex_send("block:same", "@lua/sendit/fixture.lua "),
    rex_send("block:same", "@" .. root .. "/lua/sendit/fixture.lua "),
  })
end)

test("visual send_rel_path and send_selection", function()
  rex_window()
  vim.cmd("normal! ggVj")
  sendit.send_rel_path()
  sendit.send_selection()
  vim.cmd("normal! \27")
  eq(sends(), {
    rex_send("block:same", "@lua/sendit/fixture.lua#L1-L2 "),
    rex_send("block:same", "\n```\nalpha\nbeta\n```\n"),
  })
end)

test(":Sendit selection with a range", function()
  rex_window()
  vim.cmd("normal! ggVj\27")
  vim.cmd("'<,'>Sendit selection")
  only_send(rex_send("block:same", "\n```\nalpha\nbeta\n```\n"))
end)

test("send_diagnostic", function()
  rex_window()
  local ns = vim.api.nvim_create_namespace("sendit-test")
  vim.diagnostic.set(
    ns,
    0,
    { { lnum = 0, col = 0, message = "boom\nagain", severity = vim.diagnostic.severity.ERROR } }
  )
  sendit.send_diagnostic()
  only_send(rex_send("block:same", "lua/sendit/fixture.lua:1 ERROR: boom again"))
end)

test("prompt template reaches the target", function()
  rex_window()
  prompt.select_prompt()
  only_send(rex_send("block:same", "lua/sendit/fixture.lua:1 "))
end)

test("prompt substitutions preserve percent sequences and placeholder-like selection text", function()
  rex_window()
  local selection = 'printf("%%") %0 %1 {diagnostic}'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { selection })
  vim.cmd("normal! ggV")
  pick = function(items)
    return vim.iter(items):find(function(item)
      return item == "Explain this: {selection}"
    end)
  end
  prompt.select_prompt()
  vim.cmd("normal! \27")
  only_send(rex_send("block:same", "Explain this: " .. selection))
end)

local failed = 0
for _, t in ipairs(tests) do
  local passed, err = pcall(t.fn)
  if passed then
    print("ok   " .. t.name)
  else
    failed = failed + 1
    print("FAIL " .. t.name .. "\n" .. tostring(err))
  end
end
print(("%d passed, %d failed"):format(#tests - failed, failed))
os.exit(failed == 0 and 0 or 1)
