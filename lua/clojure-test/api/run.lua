local exceptions_api = require("clojure-test.api.exceptions")
local layouts = require("clojure-test.ui.layouts")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")
local nio = require("nio")

local function go_to_test(target_window, test)
  local meta = config.backend:resolve_metadata_for_symbol(test)
  if not meta then
    return
  end

  local win = target_window
  if not vim.api.nvim_win_is_valid(win) or not utils.is_regular_buffer(vim.api.nvim_win_get_buf(win)) then
    win = utils.find_appropriate_window()
  end

  if win then
    vim.api.nvim_set_current_win(win)
  end

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
  nio.run(function()
    if event.target == "test" then
      return go_to_test(target_window, event.test)
    end

    if event.target == "exception" then
      return exceptions_api.go_to_exception(target_window, event.exception, event.frame)
    end
  end)
end

local M = {
  active_ui = nil,
  last_active_window = nil,
  unmounted = false,
}

function M.open_reports(reports)
  M.last_active_window = vim.api.nvim_get_current_win()

  local ui = M.active_ui
  if not ui then
    ui = layouts.create_layout(function(event)
      if event.type == "go-to" then
        return handle_go_to_event(M.last_active_window, event)
      end
    end)
    M.active_ui = ui
  end

  ui:mount()
  ui:render_reports(reports)
end

function M.run_tests(tests)
  if config.hooks.before_run then
    config.hooks.before_run(tests)
  end

  M.last_active_window = vim.api.nvim_get_current_win()
  M.unmounted = false

  local ui = M.active_ui
  if not ui then
    ui = layouts.create_layout(function(event)
      if event.type == "go-to" then
        return handle_go_to_event(M.last_active_window, event)
      end
      if event.type == "unmount" then
        M.unmounted = true
        M.active_ui = nil
        return
      end
    end)
    M.active_ui = ui
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
      if M.unmounted then
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
