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

  vim.api.nvim_set_hl(0, "ClojureTestFrameLocation", {
    bg = "#8BBA7F",
  })

  local lines = {}
  -- This is an index of line->frame which can be used as a lookup to compute
  -- which frame the cursor is at when doing a `gd` jump.
  local locations = {}

  local exception_title = NuiLine()
  exception_title:append(exception["class-name"], "Error")
  exception_title:append(": ", "Comment")

  local title_lines
  if exception.message ~= vim.NIL then
    title_lines = vim.split(exception.message, "\n")
  else
    title_lines = { "[NO MESSAGE]" }
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

        local indicator_highlight
        if frame.location ~= vim.NIL and frame.line ~= vim.NIL then
          indicator_highlight = "ClojureTestFrameLocation"
        end

        local frame_line = NuiLine()
        frame_line:append(" ", indicator_highlight)
        frame_line:append(" ")
        frame_line:append(namespace_and_names[1], "TSNamespace")
        frame_line:append("/", "TSMethodCall")
        frame_line:append(names, "TsMethodCall")

        if frame.line and frame.line ~= vim.NIL then
          frame_line:append(" @ ", "Comment")
          frame_line:append(tostring(frame.line), "TSNumber")
        end

        table.insert(lines, frame_line)
        locations[#lines] = frame
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

  return #lines, locations
end

-- Render a given exception chain to a specified target `buf`.
--
-- This will convert the analyzed exception into highlighted text and write it
-- as lines to the target buffer.
--
-- This API can also setup keybindings which allow per-frame (stack trace
-- frame) `go-to` actions. This is done if `opts.navigation` is passed.
--
-- Honestly, its a bit weird (architecturally speaking) that this is the
-- mechanisms for performing `go-to-definition` and a better solution should
-- probably be explored in the future. At the time of writing, it was the
-- simplest way I could think of to get the behaviour in place.
function M.render_exceptions_to_buf(buf, opts)
  local start_line = opts.start_line or 0

  vim.api.nvim_set_option_value("filetype", "clojure", {
    buf = buf,
  })
  vim.api.nvim_buf_set_lines(buf, start_line, -1, false, {})
  vim.api.nvim_buf_set_var(buf, "clojure_test_buffer_type", "exception")

  local total_lines = 0
  local locations = {}

  for _, ex in ipairs(utils.reverse_table(opts.exceptions)) do
    local lines, new_locations = M.render_exception_to_buf(buf, ex, start_line + total_lines)
    total_lines = total_lines + lines
    locations = vim.tbl_extend("force", locations, new_locations)
  end

  if opts.navigation then
    for _, chord in ipairs(utils.into_table(opts.navigation.chords)) do
      vim.keymap.set("n", chord, function()
        local buffer_type = vim.api.nvim_buf_get_var(buf, "clojure_test_buffer_type")
        if buffer_type ~= "exception" then
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(0)

        local exception = opts.exceptions[#opts.exceptions]
        local frame = locations[cursor[1]]

        opts.navigation.on_navigate(exception, frame)
      end, {
        buffer = buf,
        desc = "Go to exception origin",
      })
    end
  end

  return total_lines
end

return M
