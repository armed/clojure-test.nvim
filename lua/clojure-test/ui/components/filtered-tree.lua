local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local NuiTree = require("nui.tree")

local current_filter = "all"

local function node_to_go_to_event(node)
  if node.type == "namespace" then
    return nil
  end

  if node.test then
    return {
      type = "go-to",
      target = "test",
      test = node.test,
    }
  end

  if node.assertion then
    if node.assertion.exceptions then
      local exception = node.assertion.exceptions[#node.assertion.exceptions]
      return {
        type = "go-to",
        target = "exception",
        exception = exception,
      }
    end

    return {
      type = "go-to",
      target = "test",
      test = node.test,
    }
  end

  if not node.exception then
    return
  end

  return {
    type = "go-to",
    target = "exception",
    exception = node.exception,
  }
end

local function count_reports(reports)
  local counts = { all = 0, failed = 0, passed = 0 }
  for _, report in pairs(reports) do
    counts.all = counts.all + 1
    if report.status == "failed" then
      counts.failed = counts.failed + 1
    elseif report.status == "passed" then
      counts.passed = counts.passed + 1
    end
  end
  return counts
end

local function render_filter_panel(bufnr, counts, filter)
  local ns = vim.api.nvim_create_namespace("clojure-test-filter")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, 2)

  local all_text = string.format("All(%d)", counts.all)
  local failed_text = string.format("✗%d", counts.failed)
  local passed_text = string.format("✓%d", counts.passed)

  local all_part, failed_part, passed_part
  if filter == "all" then
    all_part = "[" .. all_text .. "]"
    failed_part = " " .. failed_text .. " "
    passed_part = " " .. passed_text .. " "
  elseif filter == "failed" then
    all_part = " " .. all_text .. " "
    failed_part = "[" .. failed_text .. "]"
    passed_part = " " .. passed_text .. " "
  else
    all_part = " " .. all_text .. " "
    failed_part = " " .. failed_text .. " "
    passed_part = "[" .. passed_text .. "]"
  end

  local line = all_part .. failed_part .. passed_part

  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { line })

  local failed_start = #all_part + 1
  local failed_end = failed_start + #failed_text
  local passed_start = #all_part + #failed_part + 1
  local passed_end = passed_start + #passed_text

  vim.api.nvim_buf_set_extmark(bufnr, ns, 0, failed_start, {
    end_col = failed_end,
    hl_group = "DiagnosticError",
  })

  vim.api.nvim_buf_set_extmark(bufnr, ns, 0, passed_start, {
    end_col = passed_end,
    hl_group = "DiagnosticOk",
  })

  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "────────────────────" })
end

local function group_reports_by_namespace(reports)
  local namespaces = {}
  local ns_order = {}

  for _, report in pairs(reports) do
    local ns = report.test:match("^([^/]+)")
    if not namespaces[ns] then
      namespaces[ns] = { ns = ns, tests = {} }
      table.insert(ns_order, ns)
    end
    table.insert(namespaces[ns].tests, report)
  end

  return namespaces, ns_order
end

local function filter_tests(tests, filter)
  if filter == "all" then
    return tests
  end

  local filtered = {}
  for _, test in ipairs(tests) do
    if filter == "failed" and test.status == "failed" then
      table.insert(filtered, test)
    elseif filter == "passed" and test.status == "passed" then
      table.insert(filtered, test)
    end
  end
  return filtered
end

local function assertion_to_line(assertion)
  local line = {}

  if assertion.type == "pass" then
    table.insert(line, NuiText(" ", "DiagnosticOk"))
    table.insert(line, NuiText("Pass"))
  else
    table.insert(line, NuiText(" ", "DiagnosticError"))
    table.insert(line, NuiText("Fail"))
  end

  if assertion.context and next(assertion.context) then
    table.insert(
      line,
      NuiText(" - " .. table.concat(utils.reverse_table(assertion.context), " "))
    )
  end

  return line
end

local function exceptions_to_nodes(exceptions)
  local nodes = {}
  for _, ex in ipairs(exceptions) do
    local line = {
      NuiText(" ", "DiagnosticWarn"),
      NuiText(ex["class-name"], "TSException"),
    }

    local node = NuiTree.Node({
      type = "exception",
      line = line,
      exception = ex,
    })
    table.insert(nodes, 1, node)
  end
  return nodes
end

local function assertion_to_node(test, assertion)
  local line = assertion_to_line(assertion)
  local children = exceptions_to_nodes(assertion.exceptions or {})

  local node = NuiTree.Node({
    type = "assertion",
    line = line,
    assertion = assertion,
    test = test,
  }, children)

  if assertion.type ~= "pass" then
    node:expand()
  end

  return node
end

local function test_to_line(report)
  local line = {}

  if report.status == "pending" then
    table.insert(line, NuiText(" "))
  elseif report.status == "failed" then
    table.insert(line, NuiText("✗ ", "DiagnosticError"))
  elseif report.status == "passed" then
    table.insert(line, NuiText("✓ ", "DiagnosticOk"))
  end

  local test_name = vim.split(report.test, "/")[2]
  table.insert(line, NuiText(test_name, "Label"))

  return line
end

local function test_to_node(report, is_expanded)
  local line = test_to_line(report)

  local children = {}
  for _, assertion in ipairs(report.assertions) do
    table.insert(children, assertion_to_node(report.test, assertion))
  end

  local node = NuiTree.Node({
    type = "report",
    line = line,
    test = report.test,
    report = report,
  }, children)

  if report.status == "failed" or is_expanded then
    node:expand()
  end
  return node
end

local function namespace_to_line(ns_name, tests, filter)
  local line = {}

  local failed_count = 0
  local passed_count = 0
  for _, test in ipairs(tests) do
    if test.status == "failed" then
      failed_count = failed_count + 1
    elseif test.status == "passed" then
      passed_count = passed_count + 1
    end
  end

  table.insert(line, NuiText(ns_name))

  if failed_count > 0 then
    table.insert(line, NuiText(" ✗" .. failed_count, "DiagnosticError"))
  end
  if passed_count > 0 then
    table.insert(line, NuiText(" ✓" .. passed_count, "DiagnosticOk"))
  end

  return line
end

local function get_empty_state_message(filter)
  if filter == "failed" then
    return "No failed tests"
  elseif filter == "passed" then
    return "No passed tests"
  end
  return "No tests"
end

local function reports_to_nodes(reports, filter, prev_nodes)
  local prev_expanded = {}
  for _, ns_node in ipairs(prev_nodes) do
    if ns_node.type == "namespace" then
      if ns_node.is_expanded and ns_node:is_expanded() then
        prev_expanded[ns_node.ns] = true
      end
      if ns_node.get_children then
        for _, child in ipairs(ns_node:get_children()) do
          if child.type == "report" and child:is_expanded() then
            prev_expanded[child.test] = true
          end
        end
      end
    end
  end

  local namespaces, ns_order = group_reports_by_namespace(reports)
  local nodes = {}

  for _, ns_name in ipairs(ns_order) do
    local ns_data = namespaces[ns_name]
    local filtered_tests = filter_tests(ns_data.tests, filter)

    local children = {}
    for _, test in ipairs(filtered_tests) do
      local is_expanded = prev_expanded[test.test]
      table.insert(children, test_to_node(test, is_expanded))
    end

    local ns_line = namespace_to_line(ns_name, ns_data.tests, filter)
    local ns_node = NuiTree.Node({
      type = "namespace",
      line = ns_line,
      ns = ns_name,
    }, children)

    local has_failed = false
    for _, test in ipairs(ns_data.tests) do
      if test.status == "failed" then
        has_failed = true
        break
      end
    end

    if has_failed or prev_expanded[ns_name] then
      ns_node:expand()
    end

    table.insert(nodes, ns_node)
  end

  return nodes
end

local M = {}

function M.create(buf, on_event)
  local tree = NuiTree({
    bufnr = buf,
    ns_id = "clojure-test-filtered-tree",
    nodes = {},
    prepare_node = function(node, tree_state)
      local line = NuiLine()

      local depth = node:get_depth()
      if depth > 1 then
        line:append(string.rep("  ", depth - 1))
      end

      if node:has_children() then
        if node:is_expanded() then
          line:append("▾ ", "Comment")
        else
          line:append("▸ ", "Comment")
        end
      else
        line:append("  ")
      end

      for _, text in ipairs(node.line) do
        line:append(text)
      end

      return line
    end,
    get_node_id = function(node)
      if node.type == "namespace" then
        return "ns:" .. node.ns
      elseif node.type == "report" then
        return "test:" .. node.test
      elseif node.type == "assertion" then
        return "assertion:" .. node.test .. ":" .. tostring(node.assertion)
      elseif node.type == "exception" then
        return "exception:" .. tostring(node.exception)
      end
      return tostring(node)
    end,
  })

  local FilteredTree = {
    tree = tree,
    buf = buf,
    reports = {},
    counts = { all = 0, failed = 0, passed = 0 },
  }

  local map_options = {
    noremap = true,
    nowait = true,
    buffer = buf,
  }

  vim.keymap.set("n", "a", function()
    if current_filter ~= "all" then
      current_filter = "all"
      FilteredTree:render_reports(FilteredTree.reports)
    end
  end, map_options)

  vim.keymap.set("n", "f", function()
    if current_filter ~= "failed" then
      current_filter = "failed"
      FilteredTree:render_reports(FilteredTree.reports)
    end
  end, map_options)

  vim.keymap.set("n", "p", function()
    if current_filter ~= "passed" then
      current_filter = "passed"
      FilteredTree:render_reports(FilteredTree.reports)
    end
  end, map_options)

  for _, chord in ipairs(utils.into_table(config.keys.ui.collapse_node)) do
    vim.keymap.set("n", chord, function()
      local linenr = vim.api.nvim_win_get_cursor(0)[1]
      local node = tree:get_node(linenr)
      if not node then
        return
      end

      if not node:has_children() or not node:is_expanded() then
        local node_id = node:get_parent_id()
        if node_id then
          node = tree:get_node(node_id)
        end
      end

      if node and node:collapse() then
        tree:render(3)
      end
    end, map_options)
  end

  for _, chord in ipairs(utils.into_table(config.keys.ui.expand_node)) do
    vim.keymap.set("n", chord, function()
      local linenr = vim.api.nvim_win_get_cursor(0)[1]
      local node = tree:get_node(linenr)
      if node and node:expand() then
        tree:render(3)
      end
    end, map_options)
  end

  for _, chord in ipairs(utils.into_table(config.keys.ui.go_to)) do
    vim.keymap.set("n", chord, function()
      local linenr = vim.api.nvim_win_get_cursor(0)[1]
      local node = tree:get_node(linenr)
      if not node then
        return
      end

      local event = node_to_go_to_event(node)
      if event then
        on_event(event)
      end
    end, map_options)
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    desc = "Track cursor in filtered-tree",
    buffer = buf,
    callback = function()
      local linenr = vim.api.nvim_win_get_cursor(0)[1]
      if linenr <= 2 then
        return
      end
      local node = tree:get_node(linenr)
      if not node then
        return
      end

      on_event({
        type = "hover",
        node = node,
      })
    end,
  })

  function FilteredTree:render_reports(reports)
    self.reports = reports
    self.counts = count_reports(reports)

    render_filter_panel(self.buf, self.counts, current_filter)

    local nodes = reports_to_nodes(reports, current_filter, tree:get_nodes())

    if #nodes == 0 and self.counts.all > 0 then
      local empty_msg = get_empty_state_message(current_filter)
      local empty_node = NuiTree.Node({
        type = "empty",
        line = { NuiText(empty_msg, "Comment") },
      })
      nodes = { empty_node }
    end

    tree:set_nodes(nodes)
    tree:render(3)
  end

  return FilteredTree
end

return M
