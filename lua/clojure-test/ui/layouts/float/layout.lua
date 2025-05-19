local NuiLayout = require("nui.layout")
local NuiPopup = require("nui.popup")

local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local function is_window_visible(win_id)
  local windows = vim.api.nvim_tabpage_list_wins(0)
  for _, id in ipairs(windows) do
    if id == win_id then
      return true
    end
  end
end

local function cycle_focus(windows, direction)
  local ordered_windows = { windows.tree, windows.left, windows.right }
  ordered_windows = vim.tbl_filter(function(window)
    return is_window_visible(window.winid)
  end, ordered_windows)

  local currently_focused_window = vim.api.nvim_get_current_win()
  local current_index = 1
  for i, win in ipairs(ordered_windows) do
    if win.winid == currently_focused_window then
      current_index = i
    end
  end

  local index = current_index + direction
  if index < 1 then
    index = #ordered_windows
  end

  if index > #ordered_windows then
    index = 1
  end

  local window = ordered_windows[index]
  vim.api.nvim_set_current_win(window.winid)
end

local function setup_bindings(popup, windows, on_event)
  for _, chord in ipairs(utils.into_table(config.keys.ui.cycle_focus_forwards)) do
    popup:map("n", chord, function()
      cycle_focus(windows, 1)
    end, { noremap = true })
  end

  for _, chord in ipairs(utils.into_table(config.keys.ui.cycle_focus_backwards)) do
    popup:map("n", chord, function()
      cycle_focus(windows, -1)
    end, { noremap = true })
  end

  local event = require("nui.utils.autocmd").event
  popup:on({ event.WinLeave }, function()
    vim.schedule(function()
      local currently_focused_window = vim.api.nvim_get_current_win()
      local found = false
      for _, win in pairs(windows) do
        if win.winid == currently_focused_window then
          found = true
        end
      end

      if found then
        return
      end

      on_event({
        type = "on-focus-lost",
      })
    end)
  end, {})
end

local M = {}

function M.create(on_event)
  local top_left_popup = NuiPopup({
    border = {
      style = "rounded",
      text = {
        top = " Expected ",
        top_align = "left",
      },
    },
  })
  local top_right_popup = NuiPopup({
    border = {
      style = "rounded",
      text = {
        top = " Result ",
        top_align = "left",
      },
    },
  })

  local report_popup = NuiPopup({
    border = {
      style = "rounded",
      text = {
        top = " Report ",
        top_align = "left",
      },
    },
    enter = true,
    focusable = true,
  })

  local double = NuiLayout.Box({
    NuiLayout.Box({
      NuiLayout.Box(top_left_popup, { grow = 1 }),
      NuiLayout.Box(top_right_popup, { grow = 1 }),
    }, { dir = "row", size = "70%" }),

    NuiLayout.Box(report_popup, { size = "30%" }),
  }, { dir = "col" })

  local single = NuiLayout.Box({
    NuiLayout.Box({
      NuiLayout.Box(top_right_popup, { grow = 1 }),
    }, { dir = "row", size = "70%" }),

    NuiLayout.Box(report_popup, { size = "30%" }),
  }, { dir = "col" })

  local layout = NuiLayout({
    position = "50%",
    relative = "editor",
    size = {
      width = 150,
      height = 60,
    },
  }, single)

  local windows = {
    tree = report_popup,
    left = top_left_popup,
    right = top_right_popup,
  }

  setup_bindings(report_popup, windows, on_event)
  setup_bindings(top_left_popup, windows, on_event)
  setup_bindings(top_right_popup, windows, on_event)

  local FloatLayout = {
    layout = layout,

    windows = windows,
  }

  function FloatLayout:map(mode, chord, fn, opts)
    windows.tree:map(mode, chord, fn, opts)
    windows.left:map(mode, chord, fn, opts)
    windows.right:map(mode, chord, fn, opts)
  end

  function FloatLayout:mount()
    layout:mount()
  end

  function FloatLayout:render_single()
    layout:update(single)
  end

  function FloatLayout:render_double()
    layout:update(double)
  end

  function FloatLayout:unmount()
    layout:unmount()
  end

  return FloatLayout
end

return M
