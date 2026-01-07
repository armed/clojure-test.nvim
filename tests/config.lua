vim.opt.runtimepath:append("./.build/dependencies/plenary.nvim")
vim.opt.runtimepath:append("./.build/dependencies/nvim-nio")
vim.opt.runtimepath:append("./.build/dependencies/nui.nvim")
vim.opt.runtimepath:append("./.build/dependencies/nvim-treesitter")
vim.opt.runtimepath:append("./.build/parsers")
vim.opt.runtimepath:append(".")

vim.cmd.runtime({ "plugin/plenary.vim", bang = true })
vim.cmd.runtime({ "plugin/nvim-nio", bang = true })
vim.cmd.runtime({ "plugin/nui.nvim", bang = true })
vim.cmd.runtime({ "plugin/nvim-treesitter.lua", bang = true })

vim.o.swapfile = false
vim.bo.swapfile = false

vim.g.mapleader = " "

require("nvim-treesitter.configs").setup({
  parser_install_dir = vim.fn.getcwd() .. "/.build/parsers",
  ensure_installed = { "clojure" },
  sync_install = true,
})

vim.keymap.set("n", "<leader>qq", function()
  vim.api.nvim_command("qa")
end, { desc = "Quit" })

require("clojure-test").setup({
  backend = require("tests.backend.mock").create(),
})
