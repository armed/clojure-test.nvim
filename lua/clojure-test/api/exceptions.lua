local components = require("clojure-test.ui.components")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")
local nio = require("nio")

local NuiPopup = require("nui.popup")

local M = {}

function M.go_to_exception(target_window, exception)
  local stack = exception["stack-trace"]
  if not stack or stack == vim.NIL then
    return
  end

  -- This will iterate over all the frames in a stack trace until a frame points to
  -- a line/file/symbol that is within the project classpath and cwd.
  --
  -- This is a bit hacky as it involves many sequential evals, but it's quick and
  -- dirty and it works.
  --
  -- Future implementation should probably do all this work in clojure land over a
  -- single eval
  for _, frame in ipairs(stack) do
    local line = frame.line
    if line == vim.NIL then
      line = nil
    end

    local symbols = {}
    if frame.package then
      table.insert(symbols, frame.package)
    end
    if frame.names[1] then
      table.insert(symbols, frame.names[1])
    end

    for _, symbol in ipairs(symbols) do
      local meta = config.backend:resolve_metadata_for_symbol(symbol)
      if meta and meta ~= vim.NIL then
        vim.api.nvim_set_current_win(target_window)
        vim.cmd("edit " .. meta.file)
        vim.schedule(function()
          vim.api.nvim_win_set_cursor(0, { line or meta.line or 1, meta.column or 0 })
        end)
        return
      end
    end
  end
end

local function open_exception_popup()
  local popup = NuiPopup({
    border = {
      style = "rounded",
      text = {
        top = " Exception ",
      },
    },
    position = "50%",
    relative = "editor",
    enter = true,
    size = {
      width = 120,
      height = 30,
    },
  })

  for _, chord in ipairs(utils.into_table(config.keys.ui.quit)) do
    popup:map("n", chord, function()
      popup:unmount()
    end, { noremap = true })
  end

  popup:mount()

  return popup
end

function M.render_exception(sym)
  local exceptions = config.backend:analyze_exception(sym)
  if not exceptions or exceptions == vim.NIL then
    return
  end

  local last_active_window = vim.api.nvim_get_current_win()

  local popup = open_exception_popup()
  components.exception.render_exceptions_to_buf(popup.bufnr, exceptions)

  local event = require("nui.utils.autocmd").event
  popup:on({ event.WinLeave }, function()
    popup:unmount()
  end, {})

  for _, chord in ipairs(utils.into_table(config.keys.ui.go_to)) do
    popup:map("n", chord, function()
      nio.run(function()
        M.go_to_exception(last_active_window, exceptions[#exceptions])
      end)
    end)
  end
end

return M
