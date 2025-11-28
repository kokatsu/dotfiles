-- https://zenn.dev/vim_jp/articles/c96e9b1bdb9241
vim.env.XDG_STATE_HOME = '/tmp'

require('config.lazy')
require('config.options')
require('config.keymaps')
require('config.autocmds')
require('config.highlights')
