local layout_api = require("clojure-test.ui.layouts.intellij.layout")
local components = require("clojure-test.ui.components")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local function handle_on_move(layout, event, on_event)
  local node = event.node

  if node.type == "namespace" then
    utils.guarded_schedule({ layout.buffers.right }, function()
      layout:render_single()
      local summary_text = string.format("Namespace: %s", node.ns)
      vim.api.nvim_buf_set_lines(layout.buffers.right, 0, -1, false, { summary_text })
    end)
    return
  end

  if node.type == "report" then
    utils.guarded_schedule({ layout.buffers.right }, function()
      layout:render_single()
      components.summary.render_summary(layout.buffers.right, node.report)
    end)
    return
  end

  if node.assertion then
    if node.assertion.exceptions then
      utils.guarded_schedule({ layout.buffers.right }, function()
        if node.assertion.expected then
          if not vim.api.nvim_buf_is_valid(layout.buffers.left) then
            return
          end
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

    utils.guarded_schedule({ layout.buffers.left, layout.buffers.right }, function()
      layout:render_double()
      components.clojure.write_clojure_to_buf(layout.buffers.left, node.assertion.expected)
      components.clojure.write_clojure_to_buf(layout.buffers.right, node.assertion.actual)
    end)
    return
  end

  if node.exception then
    utils.guarded_schedule({ layout.buffers.right }, function()
      layout:render_single()
      components.exception.render_exceptions_to_buf(layout.buffers.right, {
        exceptions = { node.exception },
      })
    end)
    return
  end

  utils.guarded_schedule({ layout.buffers.right }, function()
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
    UI.layout = layout_api.create()

    UI.layout:mount()

    UI.tree = components.filtered_tree.create(UI.layout.buffers.tree, UI.layout.windows.tree, function(event)
      if event.type == "hover" then
        return handle_on_move(UI.layout, event, on_event)
      end

      on_event(event)
    end)

    for _, chord in ipairs(utils.into_table(config.keys.ui.quit)) do
      UI.layout:map("n", chord, function()
        UI:hide()
      end, { noremap = true })
    end

    for _, chord in ipairs(utils.into_table(config.keys.ui.stop_tests)) do
      UI.layout:map("n", chord, function()
        require("clojure-test.api.run").stop_tests()
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

  function UI:hide()
    if not UI.mounted or UI.layout:is_hidden() then
      return
    end

    local is_focused = UI.layout:is_focused()
    UI.layout:hide()

    if is_focused and vim.api.nvim_win_is_valid(UI.last_active_window) then
      vim.api.nvim_set_current_win(UI.last_active_window)
    end
  end

  function UI:show()
    if not UI.mounted or not UI.layout:is_hidden() then
      return
    end

    UI.layout:show()
    UI.tree.winid = UI.layout.windows.tree
    vim.api.nvim_set_current_win(UI.layout.windows.tree)
  end

  function UI:toggle()
    if not UI.mounted then
      return false
    end

    if UI.layout:is_hidden() then
      UI:show()
    else
      UI:hide()
    end
    return true
  end

  function UI:is_hidden()
    return UI.mounted and UI.layout:is_hidden()
  end

  function UI:render_reports(reports)
    if not UI.mounted then
      return
    end
    UI.tree:render_reports(reports)
    UI.layout:resize_tree_width()
  end

  return UI
end
