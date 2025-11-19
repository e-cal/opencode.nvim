local M = {}

-- Default configuration
local defaults = {
  -- Base URL of OpenCode devserver; assuming it runs in the current workspace.
  -- You can override this if needed.
  host = "http://127.0.0.1",
  port = 8123, -- change to your OpenCode port
  -- Optional: workspace root if OpenCode expects a specific root path
  workspace_root = vim.loop.cwd(),

  -- How aggressive to reload:
  -- "buffer" - if file is open in a buffer, use :edit to reload
  -- "all"    - try to reload even if not currently visible (still just :edit on listed buffers)
  reload_mode = "buffer",

  -- Log debug messages
  debug = false,
}

local config = vim.tbl_deep_extend("force", {}, defaults)

local sse_job_id = nil

local function log(msg, level)
  level = level or vim.log.levels.INFO
  if config.debug then
    vim.notify("[opencode-minimal] " .. msg, level)
  end
end

local function build_sse_url()
  -- This depends on how OpenCode exposes its SSE endpoint.
  -- Adjust path/query to match your opencode server.
  local base = ("%s:%d"):format(config.host, config.port)
  -- Example SSE endpoint; change "/events" and query to what OpenCode uses.
  -- For a stripped-down plugin, we assume it sends events with type "file.edited"
  -- and a JSON body including a "path" (workspace-relative).
  return base .. "/events?stream=files"
end

local function parse_sse_event(lines)
  -- Very barebones SSE parsing:
  -- expect something like:
  -- event: file.edited
  -- data: {"path":"relative/path/to/file.lua"}
  local event_type
  local data_raw

  for _, line in ipairs(lines) do
    if vim.startswith(line, "event:") then
      event_type = vim.trim(line:sub(7))
    elseif vim.startswith(line, "data:") then
      data_raw = vim.trim(line:sub(6))
    end
  end

  if not event_type or not data_raw then
    return nil
  end

  local ok, data = pcall(vim.json.decode, data_raw)
  if not ok then
    log("Failed to decode SSE data: " .. tostring(data_raw), vim.log.levels.WARN)
    return nil
  end

  return {
    event = event_type,
    data = data,
  }
end

local function reload_file_if_open(abs_path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      if buf_name == abs_path then
        -- Safe reload: only if no unsaved changes
        if vim.bo[bufnr].modified then
          log("Buffer modified, skipping reload for " .. abs_path, vim.log.levels.INFO)
        else
          log("Reloading " .. abs_path, vim.log.levels.INFO)
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("edit")
          end)
        end
      end
    end
  end
end

local function handle_file_edited(rel_path)
  local root = config.workspace_root or vim.loop.cwd()
  local abs_path = vim.fs.normalize(root .. "/" .. rel_path)

  if config.reload_mode == "buffer" or config.reload_mode == "all" then
    reload_file_if_open(abs_path)
  end
end

local function start_sse_listener()
  if sse_job_id and vim.fn.jobwait({ sse_job_id }, 0)[1] == -1 then
    log("SSE listener already running", vim.log.levels.INFO)
    return
  end

  local url = build_sse_url()
  log("Connecting to OpenCode SSE at " .. url)

  -- We use curl to keep the connection open and stream SSE lines.
  -- If you prefer plenary.curl or something else, you can replace this.
  local cmd = { "curl", "-N", "--silent", url }

  local current_event_lines = {}

  sse_job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line == "" then
          -- End of one SSE event block
          if #current_event_lines > 0 then
            local evt = parse_sse_event(current_event_lines)
            current_event_lines = {}
            if evt and evt.event == "file.edited" and evt.data and evt.data.path then
              handle_file_edited(evt.data.path)
            end
          end
        else
          table.insert(current_event_lines, line)
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            log("SSE stderr: " .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function(_, code, _)
      log("SSE listener exited with code " .. tostring(code), vim.log.levels.INFO)
      sse_job_id = nil
    end,
  })

  if sse_job_id <= 0 then
    log("Failed to start SSE listener job", vim.log.levels.ERROR)
    sse_job_id = nil
  end
end

-- Public API

function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend("force", defaults, opts)
  else
    config = vim.tbl_deep_extend("force", defaults, {})
  end
end

-- Function you will bind to a key
function M.connect()
  start_sse_listener()
end

return M
