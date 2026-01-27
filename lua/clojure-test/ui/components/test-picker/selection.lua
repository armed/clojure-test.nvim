local utils = require("clojure-test.utils")

local M = {}

local persisted = {}
local persisted_filter = ""

function M.create(all_tests)
  local Selection = {
    selected = {},
    all_tests = all_tests,
  }

  local function get_tests_by_ns()
    local by_ns = {}
    for _, test in ipairs(Selection.all_tests) do
      local parsed = utils.parse_test(test)
      if not by_ns[parsed.ns] then
        by_ns[parsed.ns] = {}
      end
      table.insert(by_ns[parsed.ns], test)
    end
    return by_ns
  end

  function Selection:toggle(item, is_namespace)
    if is_namespace then
      local tests_by_ns = get_tests_by_ns()
      local ns_tests = tests_by_ns[item] or {}
      local state = self:get_namespace_state(item)

      if state == "all" then
        for _, test in ipairs(ns_tests) do
          self.selected[test] = nil
        end
      else
        for _, test in ipairs(ns_tests) do
          self.selected[test] = true
        end
      end
    else
      if self.selected[item] then
        self.selected[item] = nil
      else
        self.selected[item] = true
      end
    end
  end

  function Selection:get_namespace_state(ns)
    local tests_by_ns = get_tests_by_ns()
    local ns_tests = tests_by_ns[ns] or {}

    if #ns_tests == 0 then
      return "none"
    end

    local selected_count = 0
    for _, test in ipairs(ns_tests) do
      if self.selected[test] then
        selected_count = selected_count + 1
      end
    end

    if selected_count == 0 then
      return "none"
    elseif selected_count == #ns_tests then
      return "all"
    else
      return "partial"
    end
  end

  function Selection:is_selected(test)
    return self.selected[test] == true
  end

  function Selection:select_all(visible_tests)
    for _, test in ipairs(visible_tests) do
      self.selected[test] = true
    end
  end

  function Selection:deselect_all()
    self.selected = {}
  end

  function Selection:get_selected()
    local result = {}
    for test, _ in pairs(self.selected) do
      table.insert(result, test)
    end
    table.sort(result)
    return result
  end

  function Selection:get_selected_count()
    local count = 0
    for _, _ in pairs(self.selected) do
      count = count + 1
    end
    return count
  end

  function Selection:persist()
    persisted = vim.deepcopy(self.selected)
  end

  function Selection:restore()
    if next(persisted) then
      for test, _ in pairs(persisted) do
        if utils.included_in_table(self.all_tests, test) then
          self.selected[test] = true
        end
      end
    end
  end

  Selection:restore()

  return Selection
end

function M.clear_persisted()
  persisted = {}
  persisted_filter = ""
end

function M.persist_filter(filter)
  persisted_filter = filter or ""
end

function M.get_persisted_filter()
  return persisted_filter
end

return M
