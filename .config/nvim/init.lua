require('config.lazy')
require('ime')
require('keybinds')

vim.o.virtualedit = 'onemore'
vim.opt.mouse = 'a'
vim.opt.clipboard = 'unnamedplus'

-- tabをスペースに変換
vim.api.nvim_buf_set_option(0, 'expandtab', true)

-- https://zenn.dev/vim_jp/articles/511d7982a64967
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.winblend = 0
vim.opt.wildoptions = "pum"
vim.opt.pumblend = 5
vim.opt.background = "dark"
