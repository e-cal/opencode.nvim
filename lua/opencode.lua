local config = require("opencode.config")
local client = require("opencode.client")

local M = {}

---Setup options (called from plugin/opencode.lua or user config).
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
end

---Attach to a running OpenCode session in the current workspace.
---This starts the SSE listener.
function M.attach()
  client.start()
end

---Optionally expose a stop function.
function M.detach()
  client.stop()
end

return M
