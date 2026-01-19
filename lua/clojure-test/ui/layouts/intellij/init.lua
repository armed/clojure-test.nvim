local layout_api = require("clojure-test.ui.layouts.intellij.layout")
local components = require("clojure-test.ui.components")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local function handle_on_move(layout, event, on_event)
  local node = event.node

  if node.type == "report" then
    vim.schedule(function()
      layout:render_single()
      components.summary.render_summary(layout.buffers.right, node.report)
    end)
    return
  end

  if node.assertion then
    if node.assertion.exceptions then
      vim.schedule(function()
        if node.assertion.expected then
          layout:render_double()
          components.clojure.write_clojure_to_buf(layout.buffers.left, node.assertion.expected)
          components.exception.render_exceptions_to_buf(layout.buffers.right, {
            exceptions = node.assertion.exceptions,
            navigation = {
              chords = config.keys.ui.go_to,
              on_navigate = function(exception, frame)
                on_event({
                  type = "go-to",
                  target = "exception",
                  exception = exception,
                  frame = frame,
                })
              end,
            },
          })
          return
        end

        layout:render_single()
        components.exception.render_exceptions_to_buf(layout.buffers.right, {
          exceptions = node.assertion.exceptions,
          navigation = {
            chords = config.keys.ui.go_to,
            on_navigate = function(exception, frame)
              on_event({
                type = "go-to",
                target = "exception",
                exception = exception,
                frame = frame,
              })
            end,
          },
        })
      end)
      return
    end

    vim.schedule(function()
      layout:render_double()
      components.clojure.write_clojure_to_buf(layout.buffers.left, node.assertion.expected)
      components.clojure.write_clojure_to_buf(layout.buffers.right, node.assertion.actual)
    end)
    return
  end

  if node.exception then
    vim.schedule(function()
      layout:render_single()
      components.exception.render_exceptions_to_buf(layout.buffers.right, {
        exceptions = { node.exception },
      })
    end)
    return
  end

  vim.schedule(function()
    layout:render_single()
    components.clojure.write_clojure_to_buf(layout.buffers.right, "")
  end)
end

return function(on_event)
  local UI = {
    mounted = false,
    layout = nil,
    tree = nil,
    last_active_window = 0,
  }

  function UI:mount()
    if UI.mounted then
      return
    end

    UI.last_active_window = vim.api.nvim_get_current_win()

    UI.mounted = true
    UI.layout = layout_api.create(function(event)
      on_event(event)
    end)

    UI.layout:mount()

    UI.tree = components.tree.create(UI.layout.buffers.tree, function(event)
      if event.type == "hover" then
        return handle_on_move(UI.layout, event, on_event)
      end

      on_event(event)
    end)

    for _, chord in ipairs(utils.into_table(config.keys.ui.quit)) do
      UI.layout:map("n", chord, function()
        UI:unmount()
      end, { noremap = true })
    end
  end

  function UI:unmount()
    if not UI.mounted then
      return
    end

    local is_focused = UI.layout:is_focused()

    UI.mounted = false
    UI.layout:unmount()
    UI.layout = nil
    UI.tree = nil

    if is_focused then
      if vim.api.nvim_win_is_valid(UI.last_active_window) then
        vim.api.nvim_set_current_win(UI.last_active_window)
      end
    end

    on_event({
      type = "unmount",
    })
  end

  function UI:render_reports(reports)
    if not UI.mounted then
      return
    end
    UI.tree:render_reports(reports)
    UI.layout:resize_tree_width()
  end

  function UI:focus() end

  return UI
end
