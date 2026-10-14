local lazypath = vim.fn.stdpath('data') .. '/nix-plugins/lazy.nvim'
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

-- Setup lazy.nvim
local palette = require('utils.palette')

require('lazy').setup({
  spec = {
    -- import your plugins
    -- { import = 'plugins' },
    require('plugins.barbar'),
    require('plugins.blink'),
    require('plugins.catppuccin'),
    require('plugins.colorizer'),
    require('plugins.difftastic'),
    require('plugins.fff'),
    require('plugins.gitsigns'),
    require('plugins.lazydev'),
    require('plugins.lualine'),
    require('plugins.md-render'),
    require('plugins.mini'),
    require('plugins.moonbit'),
    require('plugins.noice'),
    require('plugins.nvim-autopairs'),
    require('plugins.nvim-lspconfig'),
    require('plugins.nvim-treesitter'),
    require('plugins.nvim-treesitter-textobjects'),
    require('plugins.octo'),
    require('plugins.peek'),
    require('plugins.pkl-neovim'),
    require('plugins.rustaceanvim'),
    require('plugins.snacks'),
    require('plugins.todo-comments'),
    require('plugins.typescript-tools'),
    require('plugins.which-key'),
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { 'catppuccin-' .. palette.flavor() } },
  -- automatically check for plugin updates
  checker = { enabled = true },
  change_detection = {
    enabled = true,
    notify = false,
  },
})
