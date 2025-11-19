local config = require("opencode.config")
local handler = require("opencode.handler")

local M = {}

local current_job_id = nil

---Stop existing SSE listener if running.
function M.stop()
  if current_job_id and current_job_id > 0 then
    vim.fn.jobstop(current_job_id)
    current_job_id = nil
    config.debug("Stopped opencode SSE listener")
  end
end

---Start listening to the OpenCode SSE endpoint.
function M.start()
  M.stop()

  local cfg = config.get()
  local url = cfg.sse_url

  config.debug("Starting SSE listener: " .. url)

  -- We use curl here; adjust as needed.
  local cmd = {
    "curl",
    "--no-buffer",
    "--silent",
    "--show-error",
    url,
  }

  local buffer = {
    event = nil,
    data_lines = {},
  }

  local function flush_event()
    if not buffer.event and #buffer.data_lines == 0 then
      return
    end

    local event_type = buffer.event or "message"
    local raw_data = table.concat(buffer.data_lines, "\n")

    local ok, decoded = pcall(vim.json.decode, raw_data)
    local payload = ok and decoded or raw_data

    handler.handle_event(event_type, payload)

    buffer.event = nil
    buffer.data_lines = {}
  end

  current_job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, lines, _)
      for _, line in ipairs(lines) do
        if line == "" or line == nil then
          flush_event()
        else
          if vim.startswith(line, "event:") then
            buffer.event = vim.trim(line:sub(#"event:" + 1))
          elseif vim.startswith(line, "data:") then
            table.insert(buffer.data_lines, vim.trim(line:sub(#"data:" + 1)))
          end
        end
      end
    end,
    on_stderr = function(_, lines, _)
      for _, line in ipairs(lines) do
        if line ~= "" then
          vim.notify("[opencode.nvim] SSE error: " .. line, vim.log.levels.WARN)
        end
      end
    end,
    on_exit = function(_, code, _)
      current_job_id = nil
      config.debug("SSE listener exited with code " .. tostring(code))
    end,
  })
end

return M
