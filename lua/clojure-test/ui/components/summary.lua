local exception = require("clojure-test.ui.components.exception")

local NuiLine = require("nui.line")
local NuiText = require("nui.text")

local M = {}

function M.render_summary(buf, report)
  vim.api.nvim_set_option_value("filetype", "clojure", {
    buf = buf,
  })

  local offset = 0

  local function render_line(items)
    NuiLine(items):render(buf, -1, offset + 1)
    offset = offset + 1
  end

  local function render_content(content)
    local lines = vim.split(vim.trim(content), "\n")
    vim.api.nvim_buf_set_lines(buf, offset, -1, false, lines)
    offset = offset + #lines
  end

  for _, assertion in ipairs(report.assertions) do
    if assertion.expected then
      render_line({ NuiText(";; Expected") })
      render_content(assertion.expected)
    end

    render_line({ NuiText(";; Actual") })
    if assertion.actual then
      render_content(assertion.actual)
    end

    if assertion.exceptions then
      local lines = exception.render_exception_to_buf(buf, assertion.exceptions[#assertion.exceptions], offset)
      offset = offset + lines
    end

    render_line({})
  end
end

return M
