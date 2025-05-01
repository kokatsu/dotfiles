local os_utils = require('utils.os')

local os_name = os_utils.detect_os()

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

local deferred_clipboard = nil
if os_name == 'wsl' and vim.fn.executable('win32yank.exe') == 1 then
  deferred_clipboard = require('plugins.deferred-clipboard')
end

-- Setup lazy.nvim
require('lazy').setup({
  spec = {
    -- import your plugins
    require('plugins.aerial'),
    require('plugins.autoclose'),
    require('plugins.barbar'),
    require('plugins.catppuccin'),
    require('plugins.copilot'),
    require('plugins.copilot-cmp'),
    require('plugins.diagram'),
    require('plugins.git-blame'),
    require('plugins.gitsigns'),
    require('plugins.hlchunk'),
    require('plugins.lualine'),
    require('plugins.neo-tree'),
    require('plugins.nvim-cmp'),
    require('plugins.nvim-lspconfig'),
    require('plugins.nvim-treesitter'),
    require('plugins.render-markdown'),
    deferred_clipboard,
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { 'catppuccin-mocha' } },
  -- automatically check for plugin updates
  checker = { enabled = true },
})
