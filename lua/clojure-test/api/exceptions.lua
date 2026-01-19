local components = require("clojure-test.ui.components")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")
local nio = require("nio")

local NuiPopup = require("nui.popup")

local M = {}

local select = nio.wrap(function(choices, opts, cb)
  vim.ui.select(choices, opts, cb)
end, 3)

local function frame_to_location(frame)
  local line = frame.line
  if line == vim.NIL then
    line = nil
  end

  if not frame.location or frame.location == vim.NIL then
    return
  end

  return {
    id = frame.id,
    file = frame.location.file,
    line = line or frame.location.line or 1,
    column = frame.location.column or 0,
  }
end

function M.go_to_exception(target_window, exception, use_frame)
  local stack = exception["stack-trace"]
  if not stack or stack == vim.NIL then
    return
  end

  local function navigate(location)
    local win = target_window
    if not vim.api.nvim_win_is_valid(win) or not utils.is_regular_buffer(vim.api.nvim_win_get_buf(win)) then
      win = utils.find_appropriate_window()
    end

    if win then
      vim.api.nvim_set_current_win(win)
    end

    vim.cmd("edit " .. location.file)
    vim.schedule(function()
      vim.api.nvim_win_set_cursor(0, { location.line, location.column })
    end)
  end

  local locations = {}
  if use_frame then
    local location = frame_to_location(use_frame)
    if location then
      return navigate(location)
    end
  end

  -- This will iterate over all the frames in a stack trace until a frame points to
  -- a line/file/symbol that is within the project classpath and cwd.
  --
  -- This is done by looking at the information inside of a frames 'location'
  -- which is populated by the clojure plugin from doing a classpath analysis.
  for _, frame in ipairs(stack) do
    local location = frame_to_location(frame)
    if location then
      table.insert(locations, location)
    end
  end

  if #locations == 0 then
    return
  end

  if #locations == 1 then
    return navigate(locations[1])
  end

  local choices = vim.tbl_map(function(location)
    return location.id
  end, locations)

  local test, index = select(choices, { prompt = "Select location" })
  if not test then
    return
  end

  local location = locations[index]
  if location then
    navigate(location)
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
  components.exception.render_exceptions_to_buf(popup.bufnr, {
    exceptions = exceptions,
    navigation = {
      chords = config.keys.ui.go_to,
      on_navigate = function(exception, frame)
        nio.run(function()
          M.go_to_exception(last_active_window, exception, frame)
        end)
      end,
    },
  })

  local event = require("nui.utils.autocmd").event
  popup:on({ event.WinLeave }, function()
    popup:unmount()
  end, {})
end

return M
