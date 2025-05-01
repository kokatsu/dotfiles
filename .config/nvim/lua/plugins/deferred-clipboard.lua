-- https://github.com/EtiamNullam/deferred-clipboard.nvim

-- https://qiita.com/hwatahik/items/32279372ea7182d75677
-- https://qiita.com/hwatahik/items/32279372ea7182d75677#comment-de6d0349a75770b4ad20

return {
  'EtiamNullam/deferred-clipboard.nvim',
  event = 'VeryLazy',
  config = function()
    require('deferred-clipboard').setup({
      fallback = 'unnamedplus',
      lazy = true,
    })
    vim.g.clipboard = {
      name = 'clip',
      copy = {
        ['+'] = 'win32yank.exe -i --crlf',
        ['*'] = 'win32yank.exe -i --crlf',
      },
      paste = {
        ['+'] = 'win32yank.exe -o --lf',
        ['*'] = 'win32yank.exe -o --lf',
      },
      cache_enable = 0,
    }
  end,
}
