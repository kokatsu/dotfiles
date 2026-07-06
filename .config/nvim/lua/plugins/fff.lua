-- https://github.com/dmtrKovalenko/fff.nvim

return {
  'dmtrKovalenko/fff.nvim',
  -- Nix ビルド版 (vimPlugins.fff-nvim, Rust バックエンド同梱) を使用。
  -- files.nix が ~/.local/share/nvim/nix-plugins/fff.nvim に symlink を配置する
  dir = vim.fn.stdpath('data') .. '/nix-plugins/fff.nvim',
  lazy = false,
  opts = {
    -- plugin/fff.lua は生の vim.g.fff.lazy_sync のみを見て nil を eager 扱いするため、
    -- 明示しないと起動時 (UIEnter) に cwd のインデックス作成が走る
    lazy_sync = true,
    layout = {
      prompt_position = 'top',
    },
    preview = {
      line_numbers = true,
    },
    grep = {
      trim_whitespace = true,
    },
  },
  keys = {
    {
      'ff',
      function()
        require('fff').find_files()
      end,
      desc = 'FFF Find Files',
    },
    {
      'fg',
      function()
        require('fff').live_grep()
      end,
      desc = 'FFF Live Grep',
    },
    {
      'fz',
      function()
        require('fff').live_grep({ grep = { modes = { 'fuzzy', 'plain' } } })
      end,
      desc = 'FFF Live Fuzzy Grep',
    },
    {
      'fw',
      function()
        require('fff').live_grep({ query = vim.fn.expand('<cword>') })
      end,
      desc = 'FFF Search Current Word',
    },
  },
}
