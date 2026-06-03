-- https://zenn.dev/vim_jp/articles/c96e9b1bdb9241
-- state ディレクトリは永続パス (~/.local/state/nvim) のまま使う
--   → trust / shada が再起動後も残り、exrc の確認が一度で済む
-- 溜まりやすい LSP ログだけ /tmp に逃がす (記事の「ログを溜めない」意図を維持)
vim.fn.mkdir('/tmp/nvim', 'p')
require('vim.lsp.log')._set_filename('/tmp/nvim/lsp.log')

require('config.lazy')
require('config.options')
require('config.keymaps')
require('config.autocmds')
require('config.highlights')

vim.cmd('packadd nvim.undotree')
