local M = {}

M.options = {
	port = nil,              -- Static port number or nil for auto-discover
	auto_connect = false,    -- Auto-connect to server on plugin load
	auto_reload = true,      -- Auto-reload files when edited by opencode
	notify_on_reload = true, -- Show notification when buffers are reloaded
	debug = false,           -- Enable debug logging for all events
}

---Setup plugin configuration
---@param opts? table User configuration options
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

---Get a config option
---@param key string Configuration key
---@return any
function M.get(key)
	return M.options[key]
end

return M
