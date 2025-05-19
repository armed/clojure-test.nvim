local config = require("clojure-test.config")

local M = {
  float = require("clojure-test.ui.layouts.float"),
}

---@class Layout
---@field mount fun(): nil
---@field unmount fun(): nil
---@field render_reports fun(self: Layout, reports: table): nil

---@param on_event fun(event: table): nil handler for emitted events
---@return Layout
function M.create_layout(on_event)
  if config.layout.layout_fn then
    return config.layout.layout_fn(on_event)
  end

  local layout_fn = M[config.layout.style]
  if not layout_fn then
    error("Unknown layout style " .. config.layout.style)
  end

  return layout_fn(on_event)
end

return M
