local M = {}

M.options = {
	port = nil,
	auto_connect = false,
	auto_reload = true,
	notify_on_reload = true,
	debug = false,
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
