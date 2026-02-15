local M = {}

---@class sendit.Config
---@field cmd string[] Shell command to run on selected text
local defaults = {
	cmd = { "tmux", "send-keys", "-t" },
	only_current_session = true, -- should only panes from the current session be listed in the picker
	selection_prefix = "", -- prefix for the selection that gets sent to the tmux pane
	path_prefix = "@", -- prefix for paths that gets sent to the tmux pane
}

---@type sendit.Config
M.config = defaults

---@param opts? sendit.Config
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", defaults, opts or {})

	vim.keymap.set("v", "<leader>as", function()
		M.send_selection()
	end, { desc = "Send selection to tmux pane" })

	local subcommands = {
		selection = M.send_selection,
	}

	vim.api.nvim_create_user_command("Sendit", function(args)
		local sub = args.fargs[1]
		local fn = subcommands[sub]
		if fn then
			fn()
		else
			vim.notify("Sendit: unknown subcommand '" .. (sub or "") .. "'", vim.log.levels.ERROR)
		end
	end, {
		nargs = 1, -- number of args the Sendit command takes
		complete = function() -- autocomplete
			return vim.tbl_keys(subcommands)
		end,
		desc = "Sendit commands",
	})
end

---@return string command
local function tmux_list_command()
	local param = M.config.only_current_session and " -s " or ""
	return "tmux list-panes" .. param .. "-F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'"
end

---@param text string
---@param pane_id string
---@return string[] command
local function tmux_send_command(text, pane_id)
	local cmd = vim.list_extend(vim.list_slice(M.config.cmd), { pane_id, text })
	return cmd
end

---@param on_select fun(pane_id: string)
local function select_pane(on_select)
	local all_panes = vim.fn.systemlist(tmux_list_command())
	local panes = vim.iter(all_panes)
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
	local cmd = tmux_send_command(text, pane_id)
	vim.system(cmd, {}, function(result)
		if result.code ~= 0 then
			vim.schedule(function()
				vim.notify("sendit: command failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
			end)
		else
			vim.notify("Sent to pane " .. pane_id)
		end
	end)
end

function M.send_selection()
	-- capture positions and mode while still in visual mode
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")
	local mode = vim.fn.mode()
	local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
	local text = M.config.selection_prefix .. table.concat(lines, "\n")

	select_pane(function(pane_id)
		send_to_pane(text, pane_id)
	end)
end

return M
