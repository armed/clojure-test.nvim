local utils = require("clojure-test.utils")

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local NuiTree = require("nui.tree")

local M = {}

local MAX_FILTER_RESULTS = 200

local function group_tests_by_namespace(tests)
  local namespaces = {}
  local ns_order = {}

  for _, test in ipairs(tests) do
    local parsed = utils.parse_test(test)
    if not namespaces[parsed.ns] then
      namespaces[parsed.ns] = { ns = parsed.ns, tests = {} }
      table.insert(ns_order, parsed.ns)
    end
    table.insert(namespaces[parsed.ns].tests, test)
  end

  return namespaces, ns_order
end

local function fuzzy_match(pattern, str)
  local pattern_lower = pattern:lower()
  local str_lower = str:lower()
  local pattern_idx = 1
  local score = 0
  local consecutive = 0

  for i = 1, #str_lower do
    if pattern_idx <= #pattern_lower and str_lower:sub(i, i) == pattern_lower:sub(pattern_idx, pattern_idx) then
      pattern_idx = pattern_idx + 1
      consecutive = consecutive + 1
      score = score + consecutive
    else
      consecutive = 0
    end
  end

  if pattern_idx > #pattern_lower then
    return score
  end
  return nil
end

local function filter_tests_by_text(tests, filter_text)
  if not filter_text or filter_text == "" then
    return tests
  end

  local scored = {}
  for _, test in ipairs(tests) do
    local score = fuzzy_match(filter_text, test)
    if score then
      table.insert(scored, { test = test, score = score })
    end
  end

  table.sort(scored, function(a, b)
    return a.score > b.score
  end)

  local result = {}
  local limit = math.min(#scored, MAX_FILTER_RESULTS)
  for i = 1, limit do
    table.insert(result, scored[i].test)
  end
  return result
end

function M.create(buf, selection, on_selection_change)
  local tests_by_ns = {}
  local debounce_timer = nil

  local tree = NuiTree({
    bufnr = buf,
    ns_id = "clojure-test-picker-tree",
    nodes = {},
    prepare_node = function(node)
      local line = NuiLine()

      local depth = node:get_depth()
      if depth > 1 then
        line:append("    ")
      end

      if node.type == "namespace" then
        if node:is_expanded() then
          line:append("▾ ", "Comment")
        else
          line:append("▸ ", "Comment")
        end
        local state = selection:get_namespace_state(node.ns)
        if state == "all" then
          line:append("[x] ", "DiagnosticOk")
        elseif state == "partial" then
          line:append("[~] ", "DiagnosticWarn")
        else
          line:append("[ ] ", "Comment")
        end
      elseif node.type == "test" then
        line:append("  ")
        if selection:is_selected(node.test) then
          line:append("[x] ", "DiagnosticOk")
        else
          line:append("[ ] ", "Comment")
        end
      end

      for _, text in ipairs(node.line) do
        line:append(text)
      end

      return line
    end,
    get_node_id = function(node)
      if node.type == "namespace" then
        return "ns:" .. node.ns
      elseif node.type == "test" then
        return "test:" .. node.test
      end
      return tostring(node)
    end,
  })

  local Tree = {
    tree = tree,
    buf = buf,
    all_tests = {},
    filter_text = "",
    visible_tests = {},
  }

  local function create_test_children(ns_name)
    local children = {}
    local ns_tests = tests_by_ns[ns_name] or {}
    for _, test in ipairs(ns_tests) do
      local parsed = utils.parse_test(test)
      local test_node = NuiTree.Node({
        type = "test",
        test = test,
        ns = parsed.ns,
        line = { NuiText(parsed.name, "Label") },
      })
      table.insert(children, test_node)
    end
    return children
  end

  function Tree:set_tests(tests)
    self.all_tests = tests
    self:apply_filter(self.filter_text)
  end

  function Tree:apply_filter(text, immediate)
    self.filter_text = text or ""

    if debounce_timer then
      debounce_timer:stop()
      debounce_timer = nil
    end

    local do_filter = function()
      local filtered = filter_tests_by_text(self.all_tests, self.filter_text)
      self.visible_tests = filtered
      self:render()
    end

    if immediate or self.filter_text == "" then
      do_filter()
    else
      debounce_timer = vim.defer_fn(do_filter, 100)
    end
  end

  function Tree:get_visible_tests()
    return self.visible_tests
  end

  function Tree:toggle_at_cursor()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    local node = tree:get_node(linenr)
    if not node then
      return
    end

    if node.type == "namespace" then
      selection:toggle(node.ns, true)
    elseif node.type == "test" then
      selection:toggle(node.test, false)
    end

    tree:render(1)
    if on_selection_change then
      on_selection_change()
    end
  end

  function Tree:expand_collapse_at_cursor()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    local node = tree:get_node(linenr)
    if not node or node.type ~= "namespace" then
      return
    end

    if node:is_expanded() then
      node:collapse()
    else
      if not node._children or #node._children == 0 then
        local children = create_test_children(node.ns)
        for _, child in ipairs(children) do
          tree:add_node(child, node:get_id())
        end
      end
      node:expand()
    end
    tree:render(1)
  end

  function Tree:expand_at_cursor()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    local node = tree:get_node(linenr)
    if not node or node.type ~= "namespace" or node:is_expanded() then
      return
    end

    node:expand()
    tree:render(1)
  end

  function Tree:collapse_at_cursor()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    local node = tree:get_node(linenr)
    if not node or node.type ~= "namespace" or not node:is_expanded() then
      return
    end

    node:collapse()
    tree:render(1)
  end

  function Tree:render()
    local prev_expanded = {}
    for _, ns_node in ipairs(tree:get_nodes()) do
      if ns_node.type == "namespace" and ns_node:is_expanded() then
        prev_expanded[ns_node.ns] = true
      end
    end

    local namespaces, ns_order = group_tests_by_namespace(self.visible_tests)
    tests_by_ns = {}
    for ns_name, ns_data in pairs(namespaces) do
      tests_by_ns[ns_name] = ns_data.tests
    end

    local nodes = {}
    for _, ns_name in ipairs(ns_order) do
      local ns_data = namespaces[ns_name]
      local test_count = #ns_data.tests

      local children = create_test_children(ns_name)
      local ns_node = NuiTree.Node({
        type = "namespace",
        ns = ns_name,
        test_count = test_count,
        line = { NuiText(ns_name .. " (" .. test_count .. ")") },
      }, children)

      if prev_expanded[ns_name] then
        ns_node:expand()
      end

      table.insert(nodes, ns_node)
    end

    tree:set_nodes(nodes)
    tree:render(1)
  end

  function Tree:get_node_at_cursor()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    return tree:get_node(linenr)
  end

  return Tree
end

return M
