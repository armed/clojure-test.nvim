local config = require("clojure-test.config")
local utils = require("clojure-test.utils")
local selection_mod = require("clojure-test.ui.components.test-picker.selection")
local tree_mod = require("clojure-test.ui.components.test-picker.tree")

local NuiLayout = require("nui.layout")
local NuiPopup = require("nui.popup")

local M = {}

local function build_winbar(filter_text, filter_focused)
  local parts = {}

  if filter_focused then
    table.insert(parts, "%#DiagnosticHint#> " .. filter_text .. "█%*")
  elseif filter_text ~= "" then
    table.insert(parts, "%#Comment#> " .. filter_text .. "%*")
  else
    table.insert(parts, "%#Comment#/ to filter%*")
  end

  return table.concat(parts, "")
end

local function build_preview_winbar(count)
  return string.format("Selected (%d tests)", count)
end

local function render_preview(buf, selection)
  local selected = selection:get_selected()
  local lines = {}

  local by_ns = {}
  local ns_order = {}
  for _, test in ipairs(selected) do
    local parsed = utils.parse_test(test)
    if not by_ns[parsed.ns] then
      by_ns[parsed.ns] = {}
      table.insert(ns_order, parsed.ns)
    end
    table.insert(by_ns[parsed.ns], parsed.name)
  end

  for _, ns in ipairs(ns_order) do
    table.insert(lines, " " .. ns)
    for _, name in ipairs(by_ns[ns]) do
      table.insert(lines, "   " .. name)
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function build_help_text()
  return " a toggle  l/h expand/collapse  <CR> run  A toggle all  q quit "
end

function M.create(tests, on_confirm, on_cancel)
  local selection = selection_mod.create(tests)

  local tree_popup = NuiPopup({
    border = {
      style = "rounded",
      text = {
        top = " Select Tests ",
        top_align = "center",
        bottom = build_help_text(),
        bottom_align = "center",
      },
    },
    enter = true,
    focusable = true,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
    win_options = {
      cursorline = true,
    },
  })

  local preview_popup = NuiPopup({
    border = {
      style = "rounded",
    },
    focusable = false,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
  })

  local layout = NuiLayout(
    {
      position = "50%",
      relative = "editor",
      size = {
        width = "80%",
        height = "70%",
      },
    },
    NuiLayout.Box({
      NuiLayout.Box(tree_popup, { size = "60%" }),
      NuiLayout.Box(preview_popup, { size = "40%" }),
    }, { dir = "row" })
  )

  local Picker = {
    layout = layout,
    tree_popup = tree_popup,
    preview_popup = preview_popup,
    selection = selection,
    tree = nil,
    filter_text = "",
    filter_focused = false,
    mounted = false,
  }

  local function update_ui()
    if not Picker.mounted then
      return
    end

    if tree_popup.winid and vim.api.nvim_win_is_valid(tree_popup.winid) then
      vim.wo[tree_popup.winid].winbar = build_winbar(Picker.filter_text, Picker.filter_focused)
    end

    if preview_popup.winid and vim.api.nvim_win_is_valid(preview_popup.winid) then
      vim.wo[preview_popup.winid].winbar = build_preview_winbar(selection:get_selected_count())
      render_preview(preview_popup.bufnr, selection)
    end
  end

  local function on_selection_change()
    update_ui()
  end

  local function setup_keybindings()
    local map_options = {
      noremap = true,
      nowait = true,
    }

    local keys = config.keys.picker or {}

    for _, chord in ipairs(utils.into_table(keys.toggle or "<Space>")) do
      tree_popup:map("n", chord, function()
        if Picker.tree then
          Picker.tree:toggle_at_cursor()
        end
      end, map_options)
    end

    for _, chord in ipairs(utils.into_table(keys.expand or "l")) do
      tree_popup:map("n", chord, function()
        if Picker.tree then
          Picker.tree:expand_at_cursor()
        end
      end, map_options)
    end

    for _, chord in ipairs(utils.into_table(keys.collapse or "h")) do
      tree_popup:map("n", chord, function()
        if Picker.tree then
          Picker.tree:collapse_at_cursor()
        end
      end, map_options)
    end

    for _, chord in ipairs(utils.into_table(keys.confirm or "<CR>")) do
      tree_popup:map("n", chord, function()
        selection:persist()
        Picker:unmount()
        if on_confirm then
          on_confirm(selection:get_selected())
        end
      end, map_options)
    end

    for _, chord in ipairs(utils.into_table(keys.toggle_all or "A")) do
      tree_popup:map("n", chord, function()
        if Picker.tree then
          local visible = Picker.tree:get_visible_tests()
          if selection:get_selected_count() > 0 then
            selection:deselect_all()
          else
            selection:select_all(visible)
          end
          Picker.tree:render()
          update_ui()
        end
      end, map_options)
    end

    for _, chord in ipairs(utils.into_table(keys.filter or "/")) do
      tree_popup:map("n", chord, function()
        Picker.filter_focused = true
        update_ui()
        Picker:start_filter_input()
      end, map_options)
    end

    for _, chord in ipairs(utils.into_table(config.keys.ui.quit or { "q", "<Esc>" })) do
      tree_popup:map("n", chord, function()
        selection:persist()
        Picker:unmount()
        if on_cancel then
          on_cancel()
        end
      end, map_options)
    end
  end

  function Picker:start_filter_input()
    local chars = {}
    for i = 32, 126 do
      table.insert(chars, string.char(i))
    end

    local filter_maps = {}

    local function cleanup_filter_maps()
      for _, map_info in ipairs(filter_maps) do
        pcall(vim.keymap.del, "n", map_info.char, { buffer = tree_popup.bufnr })
      end
      filter_maps = {}
      setup_keybindings()
    end

    local function exit_filter_mode()
      self.filter_focused = false
      cleanup_filter_maps()
      update_ui()
    end

    for _, char in ipairs(chars) do
      if char ~= "/" then
        tree_popup:map("n", char, function()
          self.filter_text = self.filter_text .. char
          if self.tree then
            self.tree:apply_filter(self.filter_text)
          end
          update_ui()
        end, { noremap = true, nowait = true })
        table.insert(filter_maps, { char = char })
      end
    end

    tree_popup:map("n", "<BS>", function()
      if #self.filter_text > 0 then
        self.filter_text = self.filter_text:sub(1, -2)
        if self.tree then
          self.tree:apply_filter(self.filter_text)
        end
        update_ui()
      end
    end, { noremap = true, nowait = true })
    table.insert(filter_maps, { char = "<BS>" })

    tree_popup:map("n", "<CR>", function()
      exit_filter_mode()
    end, { noremap = true, nowait = true })
    table.insert(filter_maps, { char = "<CR>" })

    tree_popup:map("n", "<Down>", function()
      exit_filter_mode()
    end, { noremap = true, nowait = true })
    table.insert(filter_maps, { char = "<Down>" })

    tree_popup:map("n", "<Esc>", function()
      self.filter_text = ""
      if self.tree then
        self.tree:apply_filter("")
      end
      exit_filter_mode()
    end, { noremap = true, nowait = true })
    table.insert(filter_maps, { char = "<Esc>" })
  end

  function Picker:mount()
    vim.schedule(function()
      layout:mount()
      self.mounted = true

      self.filter_text = selection_mod.get_persisted_filter()

      self.tree = tree_mod.create(tree_popup.bufnr, selection, on_selection_change)
      self.tree:set_tests(tests)

      if self.filter_text ~= "" then
        self.tree:apply_filter(self.filter_text)
      end

      setup_keybindings()

      update_ui()
    end)
  end

  function Picker:unmount()
    self.mounted = false
    selection_mod.persist_filter(self.filter_text)
    layout:unmount()
  end

  return Picker
end

return M
