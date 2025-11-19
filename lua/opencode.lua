-- local M = {}

-- M.connect = require("opencode.client").connect
-- M.detach = require("opencode.client").detach

-- return M

-- Minimal implementation to subscribe to OpenCode SSE events without Promise library
-- This demonstrates how to find the OpenCode server port and establish SSE connection

local M = {}

-- ============================================================================
-- Port Discovery Functions (from cli/server.lua)
-- ============================================================================

---Execute a shell command and return output
---@param command string
---@return string
local function exec(command)
	local executable = vim.split(command, " ")[1]
	if vim.fn.executable(executable) == 0 then
		error("`" .. executable .. "` command is not available", 0)
	end

	local handle = io.popen(command)
	if not handle then
		error("Couldn't execute command: " .. command, 0)
	end

	local output = handle:read("*a")
	handle:close()
	return output
end

---Find all OpenCode server processes
---@return table[] Array of {pid: number, port: number, cwd: string}
local function find_servers()
	if vim.fn.executable("lsof") == 0 then
		error(
			"`lsof` executable not found in `PATH` to auto-find `opencode` — please install it or set `vim.g.opencode_opts.port`",
			0
		)
	end

	local output = exec("lsof -w -iTCP -sTCP:LISTEN -P -n | grep opencode")
	if output == "" then
		error("No `opencode` processes", 0)
	end

	local servers = {}
	for line in output:gmatch("[^\r\n]+") do
		local parts = vim.split(line, "%s+")

		local pid = tonumber(parts[2])
		local port = tonumber(parts[9]:match(":(%d+)$"))
		if not pid or not port then
			error("Couldn't parse `opencode` PID and port from `lsof` entry: " .. line, 0)
		end

		local cwd = exec("lsof -w -a -p " .. pid .. " -d cwd"):match("%s+(/.*)$")
		if not cwd then
			error("Couldn't determine CWD for PID: " .. pid, 0)
		end

		table.insert(servers, {
			pid = pid,
			port = port,
			cwd = cwd,
		})
	end
	return servers
end

---Check if a process is a descendant of current Neovim instance
---@param pid number
---@return boolean
local function is_descendant_of_neovim(pid)
	local neovim_pid = vim.fn.getpid()
	local current_pid = pid

	for _ = 1, 10 do
		local parent_pid = tonumber(exec("ps -o ppid= -p " .. current_pid))
		if not parent_pid then
			error("Couldn't determine parent PID for: " .. current_pid, 0)
		end

		if parent_pid == 1 then
			return false
		elseif parent_pid == neovim_pid then
			return true
		end

		current_pid = parent_pid
	end

	return false
end

---Find OpenCode server in Neovim's CWD
---@return table {pid: number, port: number, cwd: string}
local function find_server_inside_nvim_cwd()
	local found_server
	local nvim_cwd = vim.fn.getcwd()
	for _, server in ipairs(find_servers()) do
		if server.cwd:find(nvim_cwd, 1, true) == 1 then
			found_server = server
			if is_descendant_of_neovim(server.pid) then
				break
			end
		end
	end

	if not found_server then
		error("No `opencode` process inside Neovim's CWD", 0)
	end

	return found_server
end

-- ============================================================================
-- SSE Client Functions (from cli/client.lua)
-- ============================================================================

local sse_state = {
	port = nil,
	buffer = {},
	job_id = nil,
}

---Handle SSE data stream
---@param data table
---@return table|nil
local function handle_sse(data)
	for _, line in ipairs(data) do
		if line ~= "" then
			local clean_line = (line:gsub("^data: ?", ""))
			table.insert(sse_state.buffer, clean_line)
		elseif #sse_state.buffer > 0 then
			local full_event = table.concat(sse_state.buffer)
			sse_state.buffer = {}

			local ok, response = pcall(vim.fn.json_decode, full_event)
			if ok then
				return response
			else
				vim.notify("SSE JSON decode error: " .. full_event, vim.log.levels.ERROR, { title = "opencode" })
			end
		end
	end
end

---Start listening to SSE endpoint
---@param port number
---@param callback fun(response: table)
local function listen_to_sse(port, callback)
	if sse_state.port ~= port then
		if sse_state.job_id then
			vim.fn.jobstop(sse_state.job_id)
		end

		local command = {
			"curl",
			"-s",
			"-X",
			"GET",
			"-H",
			"Content-Type: application/json",
			"-H",
			"Accept: application/json",
			"-H",
			"Accept: text/event-stream",
			"-N",
			"http://localhost:" .. port .. "/event",
		}

		local stderr_lines = {}
		local job_id = vim.fn.jobstart(command, {
			on_stdout = function(_, data)
				local response = handle_sse(data)
				if response and callback then
					callback(response)
				end
			end,
			on_stderr = function(_, data)
				if data then
					for _, line in ipairs(data) do
						table.insert(stderr_lines, line)
					end
				end
			end,
			on_exit = function(_, code)
				if code ~= 0 and code ~= 18 then
					local error_message = "curl command failed with exit code: "
						.. code
						.. "\nstderr:\n"
						.. (#stderr_lines > 0 and table.concat(stderr_lines, "\n") or "<none>")
					vim.notify(error_message, vim.log.levels.ERROR, { title = "opencode" })
				end
			end,
		})

		sse_state = {
			port = port,
			buffer = {},
			job_id = job_id,
		}
	end
end

-- ============================================================================
-- Main Subscribe Function (reimplemented without Promises)
-- ============================================================================

---Subscribe to OpenCode SSE events
---Finds the port and establishes SSE connection using callbacks instead of promises
function M.subscribe_to_sse()
	-- Try to find the port synchronously first
	local ok, server = pcall(find_server_inside_nvim_cwd)

	if ok then
		-- Port found immediately, subscribe to SSE
		local port = server.port
		vim.schedule(function()
			listen_to_sse(port, function(response)
				vim.api.nvim_exec_autocmds("User", {
					pattern = "OpencodeEvent",
					data = {
						event = response,
						port = port,
					},
				})
			end)
		end)
	else
		-- Port not found, show warning
		vim.notify("Failed to find OpenCode server: " .. tostring(server), vim.log.levels.WARN, { title = "opencode" })
	end
end

-- ============================================================================
-- Example Usage
-- ============================================================================

-- To use this minimal implementation:
--
-- 1. Load the module:
--    local opencode_sse = require("min")
--
-- 2. Subscribe to SSE events:
--    opencode_sse.subscribe_to_sse()
--
-- 3. Listen for events with an autocommand:
--    vim.api.nvim_create_autocmd("User", {
--      pattern = "OpencodeEvent",
--      callback = function(event)
--        print("Received OpenCode event:", vim.inspect(event.data))
--      end,
--    })

return M
