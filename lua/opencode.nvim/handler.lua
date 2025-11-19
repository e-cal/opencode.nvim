local config = require("opencode.config")

local M = {}

---Reload a file in Neovim if it is currently loaded in a buffer.
---@param path string Absolute or cwd-relative path.
local function reload_file(path)
  local cfg = config.get()
  local root = cfg.root_dir or vim.loop.cwd()

  -- normalize to absolute path
  if not vim.loop.fs_stat(path) then
    path = root .. "/" .. path
  end

  config.debug("Reloading file: " .. path)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname ~= "" and vim.loop.fs_realpath(bufname) == vim.loop.fs_realpath(path) then
      if vim.api.nvim_buf_is_loaded(bufnr) then
        -- Check for unsaved changes first
        if vim.api.nvim_buf_get_option(bufnr, "modified") then
          config.debug("Buffer modified, skipping reload: " .. bufname)
        else
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("checktime")
          end)
        end
      end
    end
  end
end

---Handle a generic SSE event.
---@param event_type string
---@param data table|string
function M.handle_event(event_type, data)
  if event_type == "file.edited" then
    local path
    if type(data) == "table" then
      path = data.path or data.file or data.filename
    elseif type(data) == "string" then
      -- Maybe the data payload is just a path
      path = data
    end

    if not path then
      config.debug("file.edited event missing path; data=" .. vim.inspect(data))
      return
    end

    local cfg = config.get()
    if type(cfg.map_path) == "function" then
      path = cfg.map_path(path)
    end

    reload_file(path)
  else
    config.debug("Unhandled event type: " .. tostring(event_type))
  end
end

return M
