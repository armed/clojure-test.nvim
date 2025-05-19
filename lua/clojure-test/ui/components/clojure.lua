local M = {}

function M.write_clojure_to_buf(buf, contents)
  vim.api.nvim_set_option_value("filetype", "clojure", {
    buf = buf,
  })

  local lines = {}
  if contents then
    lines = vim.split(contents, "\n")
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

return M
