-- https://zenn.dev/vim_jp/articles/c96e9b1bdb9241
vim.env.XDG_STATE_HOME = '/tmp'

-- Workaround for neovim-nightly lua treesitter query incompatibility
-- The bundled query references 'operator' field that no longer exists in lua grammar
-- Pre-set the highlights query before any lua file is opened
local query_path = vim.fn.stdpath('config') .. '/after/queries/lua/highlights.scm'
local ok, query_content = pcall(vim.fn.readfile, query_path)
if ok and query_content then
  pcall(vim.treesitter.query.set, 'lua', 'highlights', table.concat(query_content, '\n'))
end

require('config.lazy')
require('config.options')
require('config.keymaps')
require('config.autocmds')
require('config.highlights')
