local layout_api = require("clojure-test.ui.layouts.float.layout")
local components = require("clojure-test.ui.components")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local function handle_on_move(layout, event)
  local node = event.node

  if node.assertion then
    if node.assertion.exceptions then
      vim.schedule(function()
        if node.assertion.expected then
          layout:render_double()
          components.clojure.write_clojure_to_buf(layout.windows.left.bufnr, node.assertion.expected)
          components.exception.render_exceptions_to_buf(layout.windows.right.bufnr, node.assertion.exceptions)
          return
        end

        layout:render_single()
        components.exception.render_exceptions_to_buf(layout.windows.right.bufnr, node.assertion.exceptions)
      end)
      return
    end

    vim.schedule(function()
      layout:render_double()
      components.clojure.write_clojure_to_buf(layout.windows.left.bufnr, node.assertion.expected)
      components.clojure.write_clojure_to_buf(layout.windows.right.bufnr, node.assertion.actual)
    end)
    return
  end

  if node.exception then
    vim.schedule(function()
      layout:render_single()
      components.exception.render_exceptions_to_buf(layout.windows.right.bufnr, { node.exception })
    end)
    return
  end

  vim.schedule(function()
    layout:render_single()
    components.clojure.write_clojure_to_buf(layout.windows.right.bufnr, "")
  end)
end

return function(on_event)
  local UI = {
    mounted = false,
    layout = nil,
    tree = nil,

    last_active_window = vim.api.nvim_get_current_win(),
  }

  function UI:mount()
    if UI.mounted then
      return
    end

    UI.mounted = true
    UI.layout = layout_api.create(function(event)
      if event.type == "on-focus-lost" then
        if not UI.mounted then
          return
        end
        UI:unmount()
      end
    end)

    UI.layout:mount()

    UI.tree = components.tree.create(UI.layout.windows.tree.bufnr, function(event)
      if event.type == "hover" then
        return handle_on_move(UI.layout, event)
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

    UI.mounted = false
    UI.layout:unmount()
    UI.layout = nil
    UI.tree = nil

    vim.api.nvim_set_current_win(UI.last_active_window)

    on_event({
      type = "unmount",
    })
  end

  function UI:render_reports(reports)
    if not UI.mounted then
      return
    end
    UI.tree:render_reports(reports)
  end

  function UI:focus() end

  return UI
end
