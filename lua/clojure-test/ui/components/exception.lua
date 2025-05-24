local utils = require("clojure-test.utils")

local NuiLine = require("nui.line")
local NuiText = require("nui.text")

local M = {}

function M.render_exception_to_buf(buf, exception, start_line)
  start_line = start_line or 0

  vim.api.nvim_set_option_value("filetype", "clojure", {
    buf = buf,
  })
  vim.api.nvim_buf_set_lines(buf, start_line, -1, false, {})

  local lines = {}

  local exception_title = NuiLine()
  exception_title:append(exception["class-name"], "Error")
  exception_title:append(": ", "Comment")

  local title_lines
  if exception.message ~= vim.NIL then
    title_lines = vim.split(exception.message, "\n")
  else
    title_lines = {"[NO MESSAGE]"}
  end
  exception_title:append(title_lines[1], "TSParameter")

  table.insert(lines, exception_title)
  table.remove(title_lines, 1)

  for _, content in ipairs(title_lines) do
    table.insert(lines, NuiLine({ NuiText(content, "TSParameter") }))
  end

  local stack_trace = exception["stack-trace"]
  if stack_trace and stack_trace ~= vim.NIL then
    for _, frame in ipairs(stack_trace) do
      if frame.name and frame.name ~= "" then
        local namespace_and_names = vim.split(frame.name, "/")
        local names = table.concat(namespace_and_names, "/", 2)

        local frame_line = NuiLine()
        frame_line:append("  ")
        frame_line:append(namespace_and_names[1], "TSNamespace")
        frame_line:append("/", "TSMethodCall")
        frame_line:append(names, "TsMethodCall")

        if frame.line and frame.line ~= vim.NIL then
          frame_line:append(" @ ", "Comment")
          frame_line:append(tostring(frame.line), "TSNumber")
        end

        table.insert(lines, frame_line)
      end
    end
  end

  if exception.properties and exception.properties ~= vim.NIL then
    table.insert(lines, NuiLine())

    for _, content in ipairs(vim.split(exception.properties, "\n")) do
      table.insert(lines, NuiLine({ NuiText(content) }))
    end
  end

  for i, line in ipairs(lines) do
    line:render(buf, -1, start_line + i)
  end

  return #lines
end

function M.render_exceptions_to_buf(buf, exception_chain, start_line)
  start_line = start_line or 0

  vim.api.nvim_set_option_value("filetype", "clojure", {
    buf = buf,
  })
  vim.api.nvim_buf_set_lines(buf, start_line, -1, false, {})

  local total_lines = 0

  for _, ex in ipairs(utils.reverse_table(exception_chain)) do
    local lines = M.render_exception_to_buf(buf, ex, start_line + total_lines)
    total_lines = total_lines + lines
  end

  return total_lines
end

return M
