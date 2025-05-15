local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local NuiTree = require("nui.tree")

local function report_to_line(report)
  local line = {}

  if report.status == "pending" then
    table.insert(line, NuiText(" "))
  end
  if report.status == "failed" then
    table.insert(line, NuiText(" ", "Error"))
  end
  if report.status == "passed" then
    table.insert(line, NuiText(" ", "Green"))
  end

  table.insert(line, NuiText(vim.split(report.test, "/")[1], "Comment"))
  table.insert(line, NuiText("/"))
  table.insert(line, NuiText(vim.split(report.test, "/")[2], "Label"))

  return line
end

local function assertion_to_line(assertion)
  local line = {}

  if assertion.type == "pass" then
    table.insert(line, NuiText(" ", "Green"))
    table.insert(line, NuiText("Pass"))
  else
    table.insert(line, NuiText(" ", "Error"))
    table.insert(line, NuiText("Fail"))
  end

  return line
end

local function exceptions_to_nodes(exceptions)
  local nodes = {}
  for _, ex in ipairs(exceptions) do
    local line = {
      NuiText(" ", "DiagnosticWarn"),
      NuiText(ex["class-name"], "TSException"),
    }

    local node = NuiTree.Node({
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
    line = line,
    assertion = assertion,
    test = test,
  }, children)

  if assertion.type ~= "pass" then
    node:expand()
  end

  return node
end

local function report_to_node(report, is_expanded)
  local report_line = report_to_line(report)

  local children = {}
  for _, assertion in ipairs(report.assertions) do
    table.insert(children, assertion_to_node(report.test, assertion))
  end

  local node = NuiTree.Node({
    line = report_line,
    test = report.test,
    report = report,
  }, children)

  if report.status == "failed" or is_expanded then
    node:expand()
  end
  return node
end

local function reports_to_nodes(reports, prev_nodes)
  local prev_nodes_by_test = {}
  for _, node in ipairs(prev_nodes) do
    prev_nodes_by_test[node.test] = node
  end

  local nodes = {}
  for _, report in pairs(reports) do
    local prev_node = prev_nodes_by_test[report.test]
    local is_expanded = prev_node and prev_node:is_expanded()
    table.insert(nodes, report_to_node(report, is_expanded))
  end

  local curr_map = {}
  for _, node in ipairs(nodes) do
    curr_map[node.test] = node
  end

  local moved = { failed = {}, passed = {}, pending = {} }
  local grouped = { failed = {}, passed = {}, pending = {} }

  for _, prev in ipairs(prev_nodes) do
    local current = curr_map[prev.test]
    if current then
      local prev_status = prev.report.status
      local curr_status = current.report.status
      if prev_status == curr_status then
        table.insert(grouped[curr_status], current)
      elseif prev_status == "pending" and (curr_status == "failed" or curr_status == "passed") then
        table.insert(moved[curr_status], current)
      else
        table.insert(grouped[curr_status], current)
      end
      curr_map[prev.test] = nil
    end
  end

  for _, node in pairs(curr_map) do
    table.insert(grouped[node.report.status], node)
  end

  nodes = {}
  for _, status in ipairs({ "failed", "passed", "pending" }) do
    for _, n in ipairs(grouped[status]) do
      table.insert(nodes, n)
    end
    for _, n in ipairs(moved[status]) do
      table.insert(nodes, n)
    end
  end

  return nodes
end

local M = {}

function M.create(window, on_event)
  local tree = NuiTree({
    winid = window.winid,
    bufnr = vim.api.nvim_win_get_buf(window.winid),
    ns_id = "testns",
    nodes = {},
    prepare_node = function(node)
      local line = NuiLine()

      line:append(string.rep("  ", node:get_depth() - 1))

      if node:has_children() then
        if node:is_expanded() then
          line:append(" ", "Comment")
        else
          line:append(" ", "Comment")
        end
      else
        line:append("  ")
      end

      for _, text in ipairs(node.line) do
        line:append(text)
      end

      return line
    end,
  })

  local ReportTree = {
    tree = tree,
  }

  local map_options = { noremap = true, nowait = true }

  for _, chord in ipairs(utils.into_table(config.keys.ui.collapse_node)) do
    window:map("n", chord, function()
      local node = tree:get_node()
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
        tree:render()
      end
    end, map_options)
  end

  for _, chord in ipairs(utils.into_table(config.keys.ui.expand_node)) do
    window:map("n", chord, function()
      local node = tree:get_node()
      if node and node:expand() then
        tree:render()
      end
    end, map_options)
  end

  for _, chord in ipairs(utils.into_table(config.keys.ui.go_to)) do
    window:map("n", chord, function()
      local node = tree:get_node()
      if not node then
        return
      end

      on_event({
        type = "go-to",
        node = node,
      })
    end, map_options)
  end

  local event = require("nui.utils.autocmd").event
  window:on({ event.CursorMoved }, function()
    local node = tree:get_node()
    if not node then
      return
    end

    on_event({
      type = "hover",
      node = node,
    })
  end, {})

  function ReportTree:render_reports(reports)
    tree:set_nodes(reports_to_nodes(reports, tree:get_nodes()))
    tree:render()
  end

  return ReportTree
end

return M
