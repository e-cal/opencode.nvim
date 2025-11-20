local config = require("opencode.config")
local handler = require("opencode.handler")

local M = {}

---Setup the opencode plugin with user configuration
---@param opts? table User configuration options
function M.setup(opts)
	config.setup(opts)
	
	-- Auto-connect if configured
	if config.get("auto_connect") then
		vim.schedule(function()
			M.connect()
		end)
	end
end

---Connect to the OpenCode SSE server
---Attempts to find server port and establish SSE connection
function M.connect()
	handler.subscribe_to_sse()
end

---Disconnect from the OpenCode SSE server
function M.disconnect()
	handler.disconnect()
end

---Get current plugin configuration
---@param key? string Optional specific config key
---@return table|any Configuration or specific value
function M.get_config(key)
	if key then
		return config.get(key)
	end
	return config.options
end

---Connect to a server at a specific port
---@param port number Port number to connect to
function M.connect_to_port(port)
	handler.subscribe_to_sse_on_port(port)
end

return M
