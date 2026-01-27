local exceptions_api = require("clojure-test.api.exceptions")
local location = require("clojure-test.api.location")
local tests_api = require("clojure-test.api.tests")
local run_api = require("clojure-test.api.run")
local config = require("clojure-test.config")
local utils = require("clojure-test.utils")
local nio = require("nio")

local M = {}

local function ensure_connected()
  if not config.backend:is_connected() then
    vim.notify("No REPL connection. Connect to nREPL first.", vim.log.levels.ERROR)
    return false
  end
  return true
end

M.state = {
  previous = nil,
  last_run = nil,
}

local function run_tests_and_update_state(tests)
  M.state.previous = tests
  M.state.last_run = run_api.run_tests(tests)
end

local function with_exceptions(fn)
  nio.run(fn, function(success, stacktrace)
    if not success then
      vim.notify(stacktrace, vim.log.levels.ERROR)
    end
  end)
end

function M.run_all_tests()
  nio.run(function()
    if not ensure_connected() then
      return
    end
    local tests = tests_api.get_all_tests()
    if #tests == 0 then
      return
    end
    run_tests_and_update_state(tests)
  end)
end

function M.run_tests()
  with_exceptions(function()
    if not ensure_connected() then
      return
    end
    local current_test = location.get_test_at_cursor()

    local tests
    if current_test then
      tests = { current_test }
    else
      tests = tests_api.select_tests()
    end

    if #tests == 0 then
      return
    end

    run_tests_and_update_state(tests)
  end)
end

function M.run_tests_in_ns()
  with_exceptions(function()
    if not ensure_connected() then
      return
    end
    local namespaces
    local current_namespace = location.get_current_namespace()
    local test_namespaces = tests_api.get_test_namespaces()
    if current_namespace and utils.included_in_table(test_namespaces, current_namespace) then
      namespaces = { current_namespace }
    else
      namespaces = tests_api.select_namespaces()
    end

    local tests = {}
    for _, namespace in ipairs(namespaces) do
      local ns_tests = tests_api.get_tests_in_ns(namespace)
      for _, test in ipairs(ns_tests) do
        table.insert(tests, test)
      end
    end

    if #tests == 0 then
      return
    end

    run_tests_and_update_state(tests)
  end)
end

function M.rerun_previous()
  with_exceptions(function()
    if not M.state.previous then
      return
    end
    if not ensure_connected() then
      return
    end
    run_tests_and_update_state(M.state.previous)
  end)
end

function M.rerun_failed()
  with_exceptions(function()
    local failed = {}
    for test, report in pairs(M.state.last_run) do
      if report.status == "failed" then
        table.insert(failed, test)
      end
    end

    if #failed == 0 then
      vim.notify("No failed tests to run", vim.log.levels.WARN)
      return
    end

    if not ensure_connected() then
      return
    end
    run_tests_and_update_state(failed)
  end)
end

function M.open_last_report()
  if not M.state.last_run then
    return
  end
  run_api.open_reports(M.state.last_run)
end

function M.load_tests()
  with_exceptions(function()
    if not ensure_connected() then
      return
    end
    tests_api.load_tests()
  end)
end

function M.analyze_exception(sym)
  with_exceptions(function()
    if not ensure_connected() then
      return
    end
    exceptions_api.render_exception(sym)
  end)
end

function M.run_tests_in_path(path)
  with_exceptions(function()
    if not ensure_connected() then
      return
    end
    local tests = tests_api.get_tests_in_path(path)
    if not tests or type(tests) ~= "table" or #tests == 0 then
      vim.notify("No tests found in " .. path, vim.log.levels.WARN)
      return
    end
    run_tests_and_update_state(tests)
  end)
end

function M.toggle_panel()
  run_api.toggle_panel()
end

function M.stop_tests()
  run_api.stop_tests()
end

function M.run_selected_tests()
  with_exceptions(function()
    if not ensure_connected() then
      return
    end
    local tests = tests_api.select_tests_multi()
    if #tests == 0 then
      return
    end
    run_tests_and_update_state(tests)
  end)
end

return M
