local lazypath = vim.fn.stdpath('data') .. '/nix-plugins/lazy.nvim'
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

local palette = require('utils.palette')

require('lazy').setup({
  spec = {
    require('plugins.barbar'),
    require('plugins.blink'),
    require('plugins.catppuccin'),
    require('plugins.colorizer'),
    require('plugins.difftastic'),
    require('plugins.fff'),
    require('plugins.gitsigns'),
    require('plugins.lazydev'),
    require('plugins.lualine'),
    require('plugins.mini'),
    require('plugins.moonbit'),
    require('plugins.noice'),
    require('plugins.nvim-autopairs'),
    require('plugins.nvim-lspconfig'),
    require('plugins.nvim-treesitter'),
    require('plugins.nvim-treesitter-textobjects'),
    require('plugins.pkl-neovim'),
    require('plugins.rustaceanvim'),
    require('plugins.snacks'),
    require('plugins.typescript-tools'),
    require('plugins.which-key'),
  },
  install = { colorscheme = { 'catppuccin-' .. palette.flavor() } },
  checker = { enabled = true },
})
