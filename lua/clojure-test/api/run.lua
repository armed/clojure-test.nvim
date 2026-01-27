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
  stopped = false,
  current_reports = nil,
}

function M.open_reports(reports)
  M.last_active_window = vim.api.nvim_get_current_win()

  if M.active_ui then
    M.active_ui:unmount()
    M.active_ui = nil
  end

  local ui = layouts.create_layout(function(event)
    if event.type == "go-to" then
      return handle_go_to_event(M.last_active_window, event)
    end
    if event.type == "unmount" then
      M.active_ui = nil
      return
    end
  end)
  M.active_ui = ui

  ui:mount()
  ui:render_reports(reports)
end

function M.run_tests(tests)
  if config.hooks.before_run then
    config.hooks.before_run(tests)
  end

  M.last_active_window = vim.api.nvim_get_current_win()

  if M.active_ui then
    M.active_ui:unmount()
    M.active_ui = nil
  end

  M.unmounted = false
  M.stopped = false

  local ui = layouts.create_layout(function(event)
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

  ui:mount()

  M.current_reports = {}
  for _, test in ipairs(tests) do
    M.current_reports[test] = {
      test = test,
      status = "pending",
      assertions = {},
    }
  end

  ui:render_reports(M.current_reports)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "ClojureTestStarted",
    data = { total = #tests },
  })

  config.backend:run_tests_parallel_start(tests, {})

  while true do
    if M.unmounted or M.stopped then
      config.backend:stop_parallel_tests()
      break
    end

    nio.sleep(100)

    local state = config.backend:get_parallel_results()
    if state then
      for test, report in pairs(state.results or {}) do
        M.current_reports[test] = report
      end
      ui:render_reports(M.current_reports)

      if not state.running then
        break
      end
    end
  end

  local passed, failed = 0, 0
  for _, report in pairs(M.current_reports) do
    if report.status == "passed" then
      passed = passed + 1
    elseif report.status == "failed" then
      failed = failed + 1
    end
  end

  local level = failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  local msg = string.format("Tests: %d passed, %d failed", passed, failed)
  vim.notify(msg, level)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "ClojureTestFinished",
    data = { passed = passed, failed = failed, total = passed + failed },
  })

  return M.current_reports
end

function M.toggle_panel()
  if M.active_ui then
    return M.active_ui:toggle()
  end
  return false
end

function M.stop_tests()
  M.stopped = true
  if M.active_ui and M.current_reports then
    M.active_ui:render_reports(M.current_reports)
  end
end

function M.is_running()
  return M.active_ui ~= nil and not M.stopped
end

return M
