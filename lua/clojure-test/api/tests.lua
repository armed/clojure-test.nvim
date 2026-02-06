local config = require("clojure-test.config")
local utils = require("clojure-test.utils")
local nio = require("nio")

local select = nio.wrap(function(choices, opts, cb)
  vim.ui.select(choices, opts, cb)
end, 3)

local M = {}

local tests_cache = nil
local all_tests_cache = nil
local tests_by_ns_cache = nil

function M.invalidate_cache()
  tests_cache = nil
  all_tests_cache = nil
  tests_by_ns_cache = nil
end

function M.load_tests()
  vim.notify("Loading tests...", vim.log.levels.INFO)
  config.backend:load_test_namespaces()
  M.invalidate_cache()
  vim.notify("Test namespaces loaded!", vim.log.levels.INFO)
end

function M.get_all_tests()
  if all_tests_cache then
    return all_tests_cache
  end

  all_tests_cache = config.backend:get_tests()
  return all_tests_cache
end

local function refresh_cache_async(on_refresh)
  nio.run(function()
    local fresh_tests = config.backend:get_tests()
    tests_cache = fresh_tests
    all_tests_cache = fresh_tests
    tests_by_ns_cache = nil
    if on_refresh then
      vim.schedule(function()
        on_refresh(fresh_tests)
      end)
    end
  end)
end

local function build_tests_by_ns(tests)
  local grouped = {}
  for _, test in ipairs(tests) do
    local parsed = utils.parse_test(test)
    local ns_tests = grouped[parsed.ns]
    if not ns_tests then
      ns_tests = {}
      grouped[parsed.ns] = ns_tests
    end
    table.insert(ns_tests, test)
  end
  return grouped
end

function M.get_tests_by_ns()
  if tests_by_ns_cache then
    return tests_by_ns_cache
  end

  tests_by_ns_cache = build_tests_by_ns(M.get_all_tests())
  return tests_by_ns_cache
end

function M.get_test_namespaces()
  local namespaces = {}
  local tests_by_ns = M.get_tests_by_ns()
  for ns, _ in pairs(tests_by_ns) do
    table.insert(namespaces, ns)
  end
  table.sort(namespaces)
  return namespaces
end

function M.select_tests()
  local tests = M.get_all_tests()
  local test = select(tests, { prompt = "Select test" })
  if not test then
    return {}
  end
  return { test }
end

function M.select_namespaces()
  local namespaces = M.get_test_namespaces()
  local namespace = select(namespaces, { prompt = "Select namespace" })
  if not namespace then
    return {}
  end
  return { namespace }
end

function M.get_tests_in_ns(namespace)
  local tests_by_ns = M.get_tests_by_ns()
  return tests_by_ns[namespace] or {}
end

function M.get_tests_in_path(path)
  return config.backend:get_tests_in_path(path)
end

function M.select_tests_multi()
  local test_picker = require("clojure-test.ui.components.test-picker")
  local result_event = nio.control.event()
  local selected_tests = {}

  if tests_cache then
    local picker = test_picker.create(tests_cache, function(selected)
      selected_tests = selected
      result_event.set()
    end, function()
      result_event.set()
    end)
    picker:mount()

    refresh_cache_async(function(fresh_tests)
      if picker.mounted and picker.tree then
        picker.tree:set_tests(fresh_tests)
      end
    end)
  else
    vim.schedule(function()
      vim.notify("Loading tests...", vim.log.levels.INFO)
    end)

    local tests = M.get_all_tests()
    tests_cache = tests

    if #tests == 0 then
      vim.schedule(function()
        vim.notify("No tests found", vim.log.levels.WARN)
      end)
      return {}
    end

    local picker = test_picker.create(tests, function(selected)
      selected_tests = selected
      result_event.set()
    end, function()
      result_event.set()
    end)
    picker:mount()
  end

  result_event.wait()
  return selected_tests
end

return M
