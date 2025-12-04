local config = require("opencode.config")

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

local M = {}

---Find OpenCode server in Neovim's CWD
---@return table {pid: number, port: number, cwd: string}
function M.find_server_inside_nvim_cwd()
	local found_server
	local nvim_cwd = vim.fn.getcwd()
    if config.get("debug") then
        print("Neovim CWD: " .. nvim_cwd)
    end
	for _, server in ipairs(find_servers()) do
		if server.cwd:find(nvim_cwd, 1, true) == 1 then
			found_server = server
			if is_descendant_of_neovim(server.pid) then
				break
			end
		end
	end

	if not found_server then
		error("No opencode process in cwd", 0)
	end

	return found_server
end

return M
