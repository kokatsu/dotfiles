-- https://github.com/romgrk/barbar.nvim

return {
  'romgrk/barbar.nvim',
  lazy = false, -- 遅延ロードを無効化
  dependencies = {
    'lewis6991/gitsigns.nvim', -- OPTIONAL: for git status
    'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
  },
  init = function()
    vim.g.barbar_auto_setup = false
  end,
  opts = {
    -- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
    -- animation = true,
    -- insert_at_start = true,
    -- …etc.
    auto_hide = false, -- タブラインの自動非表示を無効化
  },
  version = '^1.0.0', -- optional: only update when a new 1.x version is released
  keys = {
    {
      '[b',
      '<Cmd>BufferPrevious<CR>',
      desc = 'Previous Buffer',
      mode = 'n',
      silent = true,
    },
    {
      ']b',
      '<Cmd>BufferNext<CR>',
      desc = 'Next Buffer',
      mode = 'n',
      silent = true,
    },
    {
      ',b',
      '<Cmd>BufferClose<CR>',
      desc = 'Close Buffer',
      mode = 'n',
      silent = true,
    },
  },
}
