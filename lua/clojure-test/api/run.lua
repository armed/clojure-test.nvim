local exceptions_api = require("clojure-test.api.exceptions")
local interface_api = require("clojure-test.ui")
local config = require("clojure-test.config")
local nio = require("nio")

local function go_to_test(target_window, test)
  local meta = config.backend:resolve_metadata_for_symbol(test)
  if not meta then
    return
  end

  vim.api.nvim_set_current_win(target_window)
  vim.cmd("edit " .. meta.file)
  vim.schedule(function()
    vim.api.nvim_win_set_cursor(0, { meta.line or 0, meta.column or 0 })
  end)
end

-- This function is called when <Cr> is pressed while on a node in the report
-- tree.
--
-- This function implements a kind of 'go-to-definition' for the various types
-- of nodes
local function handle_go_to_event(target_window, event)
  local node = event.node
  nio.run(function()
    if node.test then
      return go_to_test(target_window, node.test)
    end

    if node.assertion then
      if node.assertion.exceptions then
        local exception = node.assertion.exceptions[#node.assertion.exceptions]
        return exceptions_api.go_to_exception(target_window, exception)
      end

      return go_to_test(target_window, node.test)
    end

    if node.exception then
      return exceptions_api.go_to_exception(target_window, node.exception)
    end
  end)
end

local M = {}

local active_ui = nil

function M.open_reports(reports)
  local last_active_window = vim.api.nvim_get_current_win()

  local ui = active_ui
  if not ui then
    ui = interface_api.create(function(event)
      if event.type == "go-to" then
        return handle_go_to_event(last_active_window, event)
      end
    end)
    active_ui = ui
  end

  ui:mount()

  ui:render_reports(reports)
end

function M.run_tests(tests)
  if config.hooks.before_run then
    config.hooks.before_run(tests)
  end

  local state = {
    last_active_window = vim.api.nvim_get_current_win(),
    unmounted = false,
  }

  local ui = active_ui
  if not ui then
    ui = interface_api.create(function(event)
      if event.type == "go-to" then
        return handle_go_to_event(state.last_active_window, event)
      end
      if event.type == "unmount" then
        state.unmounted = true
        active_ui = nil
        return
      end
    end)
    active_ui = ui
  end

  ui:mount()

  local reports = {}
  for _, test in ipairs(tests) do
    reports[test] = {
      test = test,
      status = "pending",
      assertions = {},
    }
  end

  local queue = nio.control.queue()

  ui:render_reports(reports)

  nio.run(function()
    local semaphore = nio.control.semaphore(1)
    for _, test in ipairs(tests) do
      if state.unmounted then
        break
      end

      semaphore.with(function()
        local report = config.backend:run_test(test)
        if report then
          queue.put(report)
        end
      end)
    end
    queue.put(nil)
  end)

  while true do
    local report = queue.get()
    if report == nil then
      break
    end

    reports[report.test] = report
    ui:render_reports(reports)
  end

  return reports
end

return M
