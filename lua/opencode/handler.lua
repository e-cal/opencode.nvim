local server = require("opencode.server")
local config = require("opencode.config")

local sse_state = {
	port = nil,
	buffer = {},
	job_id = nil,
}

---Handle SSE data stream and invoke callback for each complete event
---@param data table
---@param callback fun(response: table)|nil
local function handle_sse(data, callback)
	for _, line in ipairs(data) do
		if line ~= "" then
			local clean_line = (line:gsub("^data: ?", ""))
			table.insert(sse_state.buffer, clean_line)
		elseif #sse_state.buffer > 0 then
			local full_event = table.concat(sse_state.buffer)
			sse_state.buffer = {}

			local ok, response = pcall(vim.fn.json_decode, full_event)
			if ok and callback then
				callback(response)
			elseif not ok then
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
				handle_sse(data, callback)
			end,
			on_stderr = function(_, data)
				if data then
					for _, line in ipairs(data) do
						table.insert(stderr_lines, line)
					end
				end
			end,
			on_exit = function(_, code)
				-- Exit codes: 0 = success, 18 = server closed, 143 = SIGTERM (manual disconnect)
				if code ~= 0 and code ~= 18 and code ~= 143 then
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

		-- Notify user of successful connection
		vim.notify("Connected to Opencode on port " .. port, vim.log.levels.INFO, { title = "opencode" })
	end
end

local M = {}

---Subscribe to OpenCode SSE events
---Finds the port and establishes SSE connection using callbacks instead of promises
function M.subscribe_to_sse()
	local static_port = config.get("port")

	if static_port then
		M.subscribe_to_sse_on_port(static_port)
		return
	end

	local ok, found_server = pcall(server.find_server_inside_nvim_cwd)

	if ok then
		-- Port found immediately, subscribe to SSE
		local port = found_server.port
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
		vim.notify(
			"Failed to find OpenCode server: " .. tostring(found_server),
			vim.log.levels.WARN,
			{ title = "opencode" }
		)
	end
end

---Subscribe to SSE events on a specific port
---@param port number Port to connect to
function M.subscribe_to_sse_on_port(port)
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
end

---Disconnect from SSE server
function M.disconnect()
	if sse_state.job_id then
		vim.fn.jobstop(sse_state.job_id)
		sse_state = {
			port = nil,
			buffer = {},
			job_id = nil,
		}
		vim.notify("Disconnected from Opencode", vim.log.levels.INFO, { title = "opencode" })
	end
end

return M
