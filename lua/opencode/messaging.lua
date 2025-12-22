local config = require("opencode.config")

local M = {}

---Check if cursor is on a comment using treesitter
---@return boolean
local function is_cursor_on_comment()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- Convert to 0-indexed
	local col = cursor[2]

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok then
		return false
	end

	local tree = parser:parse()[1]
	if not tree then
		return false
	end

	local node = tree:root():descendant_for_range(row, col, row, col)
	if not node then
		return false
	end

	-- Check if node or any parent is a comment
	while node do
		local node_type = node:type()
		if node_type:match("comment") then
			return true
		end
		node = node:parent()
	end

	return false
end

---Detect the comment marker pattern for a line
---@param line string
---@return string|nil The comment marker pattern (e.g., "--", "//", "#")
local function get_comment_marker(line)
	-- Match common single-line comment patterns
	local patterns = {
		"^%s*(%-%-+)%s",     -- Lua: --
		"^%s*(//+)%s",       -- C/JS: //
		"^%s*(#+)%s",        -- Python/Ruby: #
	}
	
	for _, pattern in ipairs(patterns) do
		local marker = line:match(pattern)
		if marker then
			return marker
		end
	end
	
	return nil
end

---Check if a line is a single-line comment with the given marker
---@param line string
---@param marker string The comment marker to match (e.g., "--", "//")
---@return boolean
local function is_line_single_comment(line, marker)
	if not line or not marker then
		return false
	end
	
	-- Escape special pattern characters
	local escaped_marker = marker:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
	local pattern = "^%s*" .. escaped_marker .. "%s"
	
	return line:match(pattern) ~= nil
end

---Get the full comment block at cursor position
---Merges consecutive single-line comments and handles block comments
---@return string|nil, number|nil, number|nil text, start_line, end_line (1-indexed)
local function get_comment_at_cursor()
	if not is_cursor_on_comment() then
		return nil, nil, nil
	end

    -- this is a test, ignore
    -- second line

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- Convert to 0-indexed
	local col = cursor[2]

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok then
		return nil, nil, nil
	end

	local tree = parser:parse()[1]
	if not tree then
		return nil, nil, nil
	end

	-- Find the comment node at cursor
	local node = tree:root():descendant_for_range(row, col, row, col)
	while node and not node:type():match("comment") do
		node = node:parent()
	end

	if not node then
		return nil, nil, nil
	end

	-- Get the initial comment node range
	local start_row, start_col, end_row, end_col = node:range()
	
	-- Check if this is a block comment (spans multiple lines in a single node)
	local is_block_comment = (end_row > start_row)
	
	-- For single-line comments, try to merge with adjacent single-line comments
	if not is_block_comment then
		local current_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
		local marker = get_comment_marker(current_line)
		
		if marker then
			-- Expand upwards
			local search_row = start_row - 1
			while search_row >= 0 do
				local line = vim.api.nvim_buf_get_lines(bufnr, search_row, search_row + 1, false)[1]
				if line and is_line_single_comment(line, marker) then
					start_row = search_row
					search_row = search_row - 1
				else
					break
				end
			end
			
			-- Expand downwards
			local total_lines = vim.api.nvim_buf_line_count(bufnr)
			search_row = end_row + 1
			while search_row < total_lines do
				local line = vim.api.nvim_buf_get_lines(bufnr, search_row, search_row + 1, false)[1]
				if line and is_line_single_comment(line, marker) then
					end_row = search_row
					search_row = search_row + 1
				else
					break
				end
			end
		end
	end

	-- Get all lines in the expanded range
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)

	-- Strip comment markers and trim whitespace from each line
	local trimmed_lines = {}
	for _, line in ipairs(lines) do
		-- Remove common comment markers: --, //, #, /*, */, *, <!--, -->
		local cleaned = line
			:gsub("^%s*/%*+%s*", "") -- Remove /* or /**
			:gsub("%s*%*+/%s*$", "") -- Remove */
			:gsub("^%s*%*%s?", "") -- Remove leading * (for block comments)
			:gsub("^%s*//+%s?", "") -- Remove //
			:gsub("^%s*%-%-+%s?", "") -- Remove -- (Lua comments)
			:gsub("^%s*%-%-+%[%[.*$", "") -- Remove --[[ (Lua block comment start)
			:gsub("^%s*%]%].*$", "") -- Remove ]] (Lua block comment end)
			:gsub("^%s*#+%s?", "") -- Remove #
			:gsub("^%s*<!%-%-+%s?", "") -- Remove <!--
			:gsub("%s*%-%-+>%s*$", "") -- Remove -->

		-- Trim remaining whitespace
		cleaned = cleaned:match("^%s*(.-)%s*$")

		if cleaned and cleaned ~= "" then
			table.insert(trimmed_lines, cleaned)
		end
	end

	local result = table.concat(trimmed_lines, "\n")
	-- Return 1-indexed line numbers
	return result, start_row + 1, end_row + 1
end

---Get the current session ID from the server
---@param port number
---@param callback fun(session_id: string|nil)
local function get_current_session(port, callback)
	local command = {
		"curl",
		"-s",
		"-X",
		"GET",
		"-H",
		"Content-Type: application/json",
		"http://localhost:" .. port .. "/session",
	}

	local stdout_data = {}
	vim.fn.jobstart(command, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(stdout_data, line)
				end
			end
		end,
		on_exit = function(_, code)
			if code == 0 and #stdout_data > 0 then
				local ok, sessions = pcall(vim.fn.json_decode, table.concat(stdout_data))
				if ok and sessions and #sessions > 0 then
					-- Get the first session (most recent)
					callback(sessions[1].id)
				else
					callback(nil)
				end
			else
				callback(nil)
			end
		end,
	})
end

---Send a message to OpenCode server
---@param port number The port to send to
---@param message string The message to send
---@param callback? fun(success: boolean, response: any) Optional callback for response
function M.send_message(port, message, callback)
	if not port then
		vim.notify("Not connected to OpenCode server", vim.log.levels.ERROR, { title = "opencode" })
		if callback then
			callback(false, "Not connected")
		end
		return
	end

	-- First get the current session
	get_current_session(port, function(session_id)
		if not session_id then
			vim.notify("No active session found", vim.log.levels.ERROR, { title = "opencode" })
			if callback then
				callback(false, "No active session")
			end
			return
		end

		-- Send message using prompt_async endpoint (fire and forget)
		local payload = vim.fn.json_encode({
			parts = {
				{ type = "text", text = message },
			},
		})

		local command = {
			"curl",
			"-s",
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-d",
			payload,
			"http://localhost:" .. port .. "/session/" .. session_id .. "/prompt_async",
		}

		vim.fn.jobstart(command, {
			on_exit = function(_, code)
				if code == 0 then
					if config.get("debug") then
						vim.notify("Message sent successfully", vim.log.levels.INFO, { title = "opencode" })
					end
					if callback then
						callback(true, nil)
					end
				else
					vim.notify(
						"Failed to send message (exit code: " .. code .. ")",
						vim.log.levels.ERROR,
						{ title = "opencode" }
					)
					if callback then
						callback(false, "Failed with exit code: " .. code)
					end
				end
			end,
		})
	end)
end

---Send a smart prompt: use comment at cursor or prompt user for input
---Prepends the current file path to the message
---@param port number The port to send to
---@param callback? fun(success: boolean, response: any) Optional callback for response
function M.send_smart_prompt(port, callback)
	if not port then
		vim.notify("Not connected to OpenCode server", vim.log.levels.ERROR, { title = "opencode" })
		if callback then
			callback(false, "Not connected")
		end
		return
	end

	-- Get current buffer file path
	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]

	-- Try to get comment at cursor
	local comment, start_line, end_line = get_comment_at_cursor()

	local file_context = ""
	if filepath ~= "" then
		-- Make it relative to cwd if possible
		local cwd = vim.fn.getcwd()
		if filepath:find(cwd, 1, true) == 1 then
			filepath = filepath:sub(#cwd + 2) -- +2 to skip the trailing slash
		end
		
		-- Add line range information
		local line_info
		if comment and start_line and end_line then
			if start_line == end_line then
				line_info = ":" .. start_line
			else
				line_info = ":" .. start_line .. "-" .. end_line
			end
		else
			-- No comment, use cursor line
			line_info = ":" .. cursor_line
		end
		
		file_context = "File: " .. filepath .. line_info .. "\n\n"
	end

	if comment then
		-- Send the comment as the prompt
		local message = file_context .. comment
		M.send_message(port, message, callback)
	else
		-- No comment, prompt user for input
		vim.ui.input({ prompt = "OpenCode prompt: " }, function(input)
			if input and input ~= "" then
				local message = file_context .. input
				M.send_message(port, message, callback)
			else
				if callback then
					callback(false, "No input provided")
				end
			end
		end)
	end
end

return M
