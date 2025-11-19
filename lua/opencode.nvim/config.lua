local M = {}

M.defaults = {
  -- Root directory of the workspace. By default, use current working directory.
  root_dir = vim.loop.cwd(),

  -- SSE endpoint of the running OpenCode server
  -- Adjust to match your actual OpenCode server.
  sse_url = "http://127.0.0.1:31415/events",

  -- Optional: pattern or function to map event file paths to real paths.
  -- If nil, we assume events provide absolute or cwd-relative paths.
  map_path = nil,

  -- Log level or simple boolean for debug logging.
  debug = false,
}

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

---@return table
function M.get()
  return M.options or M.defaults
end

---@param msg string
function M.debug(msg)
  local cfg = M.get()
  if cfg.debug then
    vim.notify("[opencode.nvim] " .. msg, vim.log.levels.DEBUG)
  end
end

return M
