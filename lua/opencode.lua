local config = require("opencode.config")
local handler = require("opencode.handler")
local messaging = require("opencode.messaging")

local M = {}

---Setup the opencode plugin with user configuration
---@param opts? table User configuration options
function M.setup(opts)
	config.setup(opts)

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

---Send a message to OpenCode
---@param message string The message to send
---@param callback? fun(success: boolean, response: any) Optional callback for response
function M.send_message(message, callback)
	local port = handler.get_port()
	messaging.send_message(port, message, callback)
end

---Send a smart prompt to OpenCode
---If cursor is on a comment, sends the comment. Otherwise prompts for input.
---Automatically prepends the current file path.
---@param callback? fun(success: boolean, response: any) Optional callback for response
function M.send_smart_prompt(callback)
	local port = handler.get_port()
	messaging.send_smart_prompt(port, callback)
end

return M
