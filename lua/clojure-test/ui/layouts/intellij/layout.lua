local config = require("clojure-test.config")
local utils = require("clojure-test.utils")

local M = {}

local function create_scratch_buffer(filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = filetype
  return bufnr
end

local function calculate_height()
  local height_percent = (config.layout.intellij and config.layout.intellij.height_percent) or 30
  return math.floor(vim.o.lines * height_percent / 100)
end

local function is_window_valid(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function cycle_focus(windows, direction)
  local ordered_windows = { windows.tree, windows.left, windows.right }
  ordered_windows = vim.tbl_filter(function(winid)
    return is_window_valid(winid)
  end, ordered_windows)

  local currently_focused = vim.api.nvim_get_current_win()
  local current_index = 1
  for i, winid in ipairs(ordered_windows) do
    if winid == currently_focused then
      current_index = i
    end
  end

  local index = current_index + direction
  if index < 1 then
    index = #ordered_windows
  end
  if index > #ordered_windows then
    index = 1
  end

  vim.api.nvim_set_current_win(ordered_windows[index])
end

function M.create()
  local Layout = {
    windows = {
      tree = nil,
      left = nil,
      right = nil,
    },
    buffers = {
      tree = nil,
      left = nil,
      right = nil,
    },
    mounted = false,
    hidden = false,
    mode = "single",
  }

  function Layout:_create_windows()
    local height = calculate_height()

    vim.cmd("botright " .. height .. "split")
    local main_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(main_winid, self.buffers.tree)
    vim.wo[main_winid].winfixheight = true
    vim.wo[main_winid].number = false
    vim.wo[main_winid].relativenumber = false
    vim.wo[main_winid].signcolumn = "no"

    vim.cmd("vsplit")
    local right_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(right_winid, self.buffers.right)
    vim.wo[right_winid].winfixheight = true

    self.windows.tree = main_winid
    self.windows.right = right_winid
    self.windows.left = nil

    if self.mode == "double" then
      vim.api.nvim_set_current_win(self.windows.right)
      vim.cmd("leftabove vsplit")
      local left_winid = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(left_winid, self.buffers.left)
      vim.wo[left_winid].winfixheight = true
      self.windows.left = left_winid
    end

    vim.api.nvim_set_current_win(self.windows.tree)
    self:_setup_bindings()
  end

  function Layout:mount()
    if self.mounted and self.hidden then
      self:show()
      return
    end

    if self.mounted then
      return
    end

    self.buffers.tree = create_scratch_buffer("clojure-test-tree")
    self.buffers.left = create_scratch_buffer("clojure-test-output")
    self.buffers.right = create_scratch_buffer("clojure-test-output")

    self.mode = "single"
    self.mounted = true
    self.hidden = false

    self:_create_windows()
  end

  function Layout:unmount()
    if not self.mounted then
      return
    end

    for name, winid in pairs(self.windows) do
      if is_window_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
      self.windows[name] = nil
    end

    for name, bufnr in pairs(self.buffers) do
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      self.buffers[name] = nil
    end

    self.mounted = false
    self.hidden = false
    self.mode = "single"
  end

  function Layout:hide()
    if not self.mounted or self.hidden then
      return
    end

    for name, winid in pairs(self.windows) do
      if is_window_valid(winid) then
        vim.api.nvim_win_close(winid, true)
      end
      self.windows[name] = nil
    end

    self.hidden = true
  end

  function Layout:show()
    if not self.mounted or not self.hidden then
      return
    end

    self.hidden = false
    self:_create_windows()
  end

  function Layout:toggle()
    if self.hidden then
      self:show()
    else
      self:hide()
    end
  end

  function Layout:is_hidden()
    return self.hidden
  end

  function Layout:render_single()
    if not self.mounted then
      return
    end

    if self.mode == "single" then
      return
    end

    local current_win = vim.api.nvim_get_current_win()
    local was_left_focused = current_win == self.windows.left

    if is_window_valid(self.windows.left) then
      vim.api.nvim_win_close(self.windows.left, true)
      self.windows.left = nil
    end

    self.mode = "single"

    if was_left_focused then
      if is_window_valid(self.windows.right) then
        vim.api.nvim_set_current_win(self.windows.right)
      end
    elseif is_window_valid(current_win) then
      vim.api.nvim_set_current_win(current_win)
    end
  end

  function Layout:render_double()
    if not self.mounted then
      return
    end

    if self.mode == "double" then
      return
    end

    local current_win = vim.api.nvim_get_current_win()

    vim.api.nvim_set_current_win(self.windows.right)
    vim.cmd("leftabove vsplit")
    local left_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(left_winid, self.buffers.left)
    vim.wo[left_winid].winfixheight = true

    self.windows.left = left_winid
    self.mode = "double"

    self:_setup_window_bindings(left_winid)

    if is_window_valid(current_win) then
      vim.api.nvim_set_current_win(current_win)
    end
  end

  function Layout:is_focused()
    local current = vim.api.nvim_get_current_win()
    for _, winid in pairs(self.windows) do
      if winid == current then
        return true
      end
    end
    return false
  end

  function Layout:map(mode, chord, fn, opts)
    for _, bufnr in pairs(self.buffers) do
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.keymap.set(mode, chord, fn, vim.tbl_extend("force", opts or {}, { buffer = bufnr }))
      end
    end
  end

  function Layout:resize_tree_width()
    if not is_window_valid(self.windows.tree) then
      return
    end

    local winbar = vim.wo[self.windows.tree].winbar or ""
    local winbar_width = vim.fn.strdisplaywidth(winbar:gsub("%%#%w+#", ""):gsub("%%*", ""):gsub("%%=", ""))

    local lines = vim.api.nvim_buf_get_lines(self.buffers.tree, 0, -1, false)
    local max_width = math.max(20, winbar_width)
    local surroundings_offet = 3
    for _, line in ipairs(lines) do
      max_width = math.max(max_width, vim.fn.strdisplaywidth(line) + surroundings_offet)
    end

    vim.api.nvim_win_set_width(self.windows.tree, max_width)
  end

  function Layout:_setup_bindings()
    for _, winid in pairs(self.windows) do
      if is_window_valid(winid) then
        self:_setup_window_bindings(winid)
      end
    end
  end

  function Layout:_setup_window_bindings(winid)
    local bufnr = vim.api.nvim_win_get_buf(winid)

    for _, chord in ipairs(utils.into_table(config.keys.ui.cycle_focus_forwards)) do
      vim.keymap.set("n", chord, function()
        cycle_focus(self.windows, 1)
      end, { buffer = bufnr, noremap = true })
    end

    for _, chord in ipairs(utils.into_table(config.keys.ui.cycle_focus_backwards)) do
      vim.keymap.set("n", chord, function()
        cycle_focus(self.windows, -1)
      end, { buffer = bufnr, noremap = true })
    end
  end

  return Layout
end

return M
