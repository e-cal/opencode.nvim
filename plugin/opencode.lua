local config = require("opencode.config")

-- Setup event handling for opencode events
vim.api.nvim_create_autocmd("User", {
	group = vim.api.nvim_create_augroup("OpencodeAutoReload", { clear = true }),
	pattern = "OpencodeEvent",
	callback = function(args)
		local event = args.data.event
		local debug = config.get("debug")

		if debug then
			print("OpenCode Event: " .. event.type)
		end

		if event.type == "file.edited" then
			local auto_reload = config.get("auto_reload")
			if not auto_reload then
				return
			end

			if not vim.o.autoread then
				vim.notify(
					"Please set `vim.o.autoread = true` to use `opencode.nvim` auto-reload, or disable with `auto_reload = false` in setup()",
					vim.log.levels.WARN,
					{ title = "opencode" }
				)
			else
				-- `schedule` because blocking the event loop during rapid SSE influx can drop events
				vim.schedule(function()
					-- `:checktime` checks all buffers - no need to check the event's file
					vim.cmd("checktime")

					-- Notify if configured
					if config.get("notify_on_reload") then
						vim.notify("Buffers reloaded", vim.log.levels.INFO, { title = "opencode" })
					end
				end)
			end
		end
	end,
	desc = "Reload buffers edited by `opencode`",
})

-- User command to connect to OpenCode
vim.api.nvim_create_user_command("OpencodeConnect", function()
	require("opencode").connect()
end, {
	desc = "Connect to OpenCode SSE server for auto-reloading files",
})

vim.api.nvim_create_user_command("OpencodeDisconnect", function()
	require("opencode").disconnect()
end, {
	desc = "Disconnect from OpenCode SSE server",
})
