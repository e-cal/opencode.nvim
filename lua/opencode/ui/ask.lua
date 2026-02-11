---@module 'snacks.input'

local M = {}

---@return snacks.win.Config
local function cursor_input_win_layout()
  return {
    title_pos = "left",
    relative = "cursor",
    row = -3, -- Row above the cursor
    col = 0, -- Align with the cursor
  }
end

---@param keys string|string[]|nil
---@return string[]
local function normalize_keys(keys)
  if type(keys) == "string" then
    return { keys }
  end
  if vim.islist(keys) then
    return keys
  end
  return {}
end

---@param buf number
---@param mode_keys table<string, string[]|string>|nil
---@param callback function
local function set_mode_keymaps(buf, mode_keys, callback)
  if not mode_keys then
    return
  end
  for mode, keys in pairs(mode_keys) do
    for _, lhs in ipairs(normalize_keys(keys)) do
      vim.keymap.set(mode, lhs, callback, { buffer = buf, nowait = true, silent = true })
    end
  end
end

---@param buf number
---@param context opencode.Context
---@param ns number
local function highlight_buffer(buf, context, ns)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local rendered = context:render(text)
  local extmarks = context.extmarks(rendered.input)

  for _, extmark in ipairs(extmarks) do
    vim.api.nvim_buf_set_extmark(buf, ns, (extmark.row or 1) - 1, extmark.col, {
      end_col = extmark.end_col,
      hl_group = extmark.hl_group,
    })
  end
end

---@param ask_opts opencode.ask.Opts
local function setup_blink_cmp(ask_opts)
  if package.loaded["blink.cmp"] then
    require("opencode.cmp.blink").setup(ask_opts.blink_cmp_sources)
  end
end

---@param default? string
---@param opts opencode.api.prompt.Opts
---@param ask_opts opencode.ask.Opts
---@return opencode.Promise
local function buffer_input(default, opts, ask_opts)
  return require("opencode.promise").new(function(resolve)
    local buffer_opts = ask_opts.buffer
    local width = math.max(buffer_opts.min_width, math.floor(vim.o.columns * buffer_opts.width_ratio))
    local height = math.max(buffer_opts.min_height, math.floor(vim.o.lines * buffer_opts.height_ratio))
    local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = buffer_opts.border,
      title = " " .. ask_opts.prompt .. " ",
      title_pos = buffer_opts.title_pos,
    })

    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "opencode_ask"
    vim.bo[buf].buftype = ""
    vim.bo[buf].swapfile = false
    vim.wo[win].wrap = buffer_opts.linewrap
    vim.wo[win].linebreak = buffer_opts.linewrap

    if buffer_opts.linewrap then
      vim.keymap.set("n", "j", "gj", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "k", "gk", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "0", "g0", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "^", "g^", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "$", "g$", { buffer = buf, nowait = true, silent = true })
    end

    local initial = default and vim.split(default, "\n", { plain = true, trimempty = false }) or { "" }
    if #initial == 0 then
      initial = { "" }
    end
    if default and default ~= "" and initial[#initial] ~= "" then
      table.insert(initial, "")
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)
    vim.api.nvim_win_set_cursor(win, { #initial, 0 })

    local ns = vim.api.nvim_create_namespace("opencode_ask_highlight")
    highlight_buffer(buf, opts.context, ns)

    local done = false
    local function finish(value)
      if done then
        return
      end
      done = true
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      resolve(value)
    end

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      callback = function()
        highlight_buffer(buf, opts.context, ns)
      end,
    })

    vim.api.nvim_create_autocmd("InsertEnter", {
      once = true,
      buffer = buf,
      callback = function()
        setup_blink_cmp(ask_opts)
      end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
      once = true,
      pattern = tostring(win),
      callback = function()
        finish(false)
      end,
    })

    local submit = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local value = table.concat(lines, "\n")
      if value ~= "" then
        finish(value)
      else
        finish(false)
      end
    end

    if buffer_opts.submit_on_write then
      vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf,
        callback = submit,
      })
    end

    set_mode_keymaps(buf, buffer_opts.submit_keys, submit)
    set_mode_keymaps(buf, buffer_opts.cancel_keys, function()
      finish(false)
    end)

    setup_blink_cmp(ask_opts)
    if buffer_opts.start_insert then
      vim.cmd("startinsert")
    end
  end)
end

---@class opencode.ask.Opts
---
---Text of the prompt.
---@field prompt? string
---
---Completion sources to automatically register when using [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md) and [`blink.cmp`](https://github.com/Saghen/blink.cmp).
---The `"opencode"` source offers completions and previews for contexts and `opencode` subagents.
---@field blink_cmp_sources? string[]
---
---Where to position the ask input UI.
---`"input"` uses `vim.ui.input` (for example, `snacks.input`).
---`"buffer"` uses a centered floating buffer for multi-line prompts.
---@field capture? "input"|"buffer"
---
---@class opencode.ask.BufferOpts
---@field width_ratio? number Buffer width as a fraction of `vim.o.columns`.
---@field height_ratio? number Buffer height as a fraction of `vim.o.lines`.
---@field min_width? number Minimum buffer width.
---@field min_height? number Minimum buffer height.
---@field border? string Border style for the floating window.
---@field title_pos? "left"|"center"|"right" Title alignment.
---@field linewrap? boolean Enable both `wrap` and `linebreak`.
---@field submit_on_write? boolean Submit when writing the buffer.
---@field start_insert? boolean Enter insert mode when opening.
---@field submit_keys? table<string, string[]|string> Keys to submit by mode.
---@field cancel_keys? table<string, string[]|string> Keys to cancel by mode.
---
---Options for buffer capture mode.
---@field buffer? opencode.ask.BufferOpts
---
---Options for [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field snacks? snacks.input.Opts

---Input a prompt for `opencode`.
---
--- - Press the up arrow to browse recent asks.
--- - Highlights and completes contexts and `opencode` subagents.
---   - Press `<Tab>` to trigger built-in completion.
---   - Registers `opts.ask.blink_cmp_sources` when using `snacks.input` and `blink.cmp`.
---
---@param default? string Text to pre-fill the input with.
---@param opts? opencode.api.prompt.Opts Options for `prompt()`.
function M.ask(default, opts)
  opts = opts or {}
  local ask_opts = require("opencode.config").opts.ask
  local capture = ask_opts.capture
  if not capture and ask_opts.layout == "centered" then
    capture = "buffer"
  elseif not capture then
    capture = "input"
  end
  opts.context = opts.context or require("opencode.context").new()
  require("opencode.cmp.blink").context = opts.context

  ---@type snacks.input.Opts
  local input_opts = {
    default = default,
    highlight = function(text)
      local rendered = opts.context:render(text)
      -- Transform to `:help input()-highlight` format
      return vim.tbl_map(function(extmark)
        return { extmark.col, extmark.end_col, extmark.hl_group }
      end, opts.context.extmarks(rendered.input))
    end,
    completion = "customlist,v:lua.opencode_completion",
    -- `snacks.input`-only options
    win = vim.tbl_deep_extend("force", cursor_input_win_layout(), {
      b = {
        -- Enable `blink.cmp` completion
        completion = true,
      },
      bo = {
        -- Custom filetype to enable `blink.cmp` source on
        filetype = "opencode_ask",
      },
      on_buf = function(win)
        -- Wait as long as possible to check for `blink.cmp` loaded - many users lazy-load on `InsertEnter`.
        -- And OptionSet :runtimepath didn't seem to fire for lazy.nvim. And/or it may never fire if already loaded.
        vim.api.nvim_create_autocmd("InsertEnter", {
          once = true,
          buffer = win.buf,
          callback = function()
            setup_blink_cmp(ask_opts)
          end,
        })
      end,
    }),
  }
  -- Nest `snacks.input` options under `opts.ask.snacks` for consistency with other `snacks`-exclusive config,
  -- and to keep its fields optional. Double-merge is kinda ugly but seems like the lesser evil.
  input_opts = vim.tbl_deep_extend("force", input_opts, ask_opts)
  input_opts = vim.tbl_deep_extend("force", input_opts, ask_opts.snacks)

  require("opencode.cli.server")
    .get_port()
    :next(function(port) ---@param port number
      return require("opencode.promise").new(function(resolve)
        require("opencode.cli.client").get_agents(port, function(agents)
          opts.context.agents = vim.tbl_filter(function(agent)
            return agent.mode == "subagent"
          end, agents)

          resolve(true)
        end)
      end)
    end)
    :next(function()
      if capture == "buffer" then
        return buffer_input(default, opts, ask_opts)
      end

      return require("opencode.promise").new(function(resolve)
        vim.ui.input(input_opts, function(value)
          if value and value ~= "" then
            resolve(value)
          else
            resolve(false)
          end
        end)
      end)
    end)
    :next(function(input) ---@param input string|false
      if input then
        require("opencode").prompt(input, opts)
      else
        opts.context:resume()
      end
      return true
    end)
    :catch(function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end)
    :finally(function()
      opts.context:clear()
    end)
end

-- FIX: Overridden by blink.cmp cmdline completion if both are enabled, and that won't have our items.
-- Possible to register our blink source there? But only active in our own vim.ui.input calls.

---Completion function for context placeholders and `opencode` subagents.
---Must be a global variable for use with `vim.ui.select`.
---
---@param ArgLead string The text being completed.
---@param CmdLine string The entire current input line.
---@param CursorPos number The cursor position in the input line.
---@return table<string> items A list of filtered completion items.
_G.opencode_completion = function(ArgLead, CmdLine, CursorPos)
  -- Not sure if it's me or vim, but ArgLead = CmdLine... so we have to parse and complete the entire line, not just the last word.
  local start_idx, end_idx = CmdLine:find("([^%s]+)$")
  local latest_word = start_idx and CmdLine:sub(start_idx, end_idx) or nil

  local completions = {}
  for placeholder, _ in pairs(require("opencode.config").opts.contexts) do
    table.insert(completions, placeholder)
  end
  for _, agent in ipairs(require("opencode.cmp.blink").context.agents or {}) do
    table.insert(completions, "@" .. agent.name)
  end

  local items = {}
  for _, completion in pairs(completions) do
    if not latest_word then
      local new_cmd = CmdLine .. completion
      table.insert(items, new_cmd)
    elseif completion:find(latest_word, 1, true) == 1 then
      local new_cmd = CmdLine:sub(1, start_idx - 1) .. completion .. CmdLine:sub(end_idx + 1)
      table.insert(items, new_cmd)
    end
  end
  return items
end

return M
