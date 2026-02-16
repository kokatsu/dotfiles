-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { out, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

-- Setup lazy.nvim
require('lazy').setup({
  spec = {
    -- import your plugins
    -- { import = 'plugins' },
    require('plugins.barbar'),
    require('plugins.blink'),
    require('plugins.catppuccin'),
    require('plugins.colorizer'),
    require('plugins.diffview'),
    require('plugins.flash'),
    require('plugins.git-blame'),
    require('plugins.gitsigns'),
    require('plugins.lazydev'),
    require('plugins.lualine'),
    require('plugins.mini'),
    require('plugins.noice'),
    require('plugins.nvim-autopairs'),
    require('plugins.nvim-lint'),
    require('plugins.nvim-lspconfig'),
    require('plugins.nvim-treesitter'),
    require('plugins.octo'),
    require('plugins.peek'),
    require('plugins.rustaceanvim'),
    require('plugins.sidekick'),
    require('plugins.snacks'),
    require('plugins.swagger-preview'),
    require('plugins.trouble'),
    require('plugins.typescript-tools'),
    require('plugins.which-key'),
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { 'catppuccin-mocha' } },
  -- automatically check for plugin updates
  checker = { enabled = true },
  change_detection = {
    enabled = true,
    notify = false,
  },
})
