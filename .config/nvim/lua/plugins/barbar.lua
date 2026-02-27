-- https://github.com/romgrk/barbar.nvim

return {
  'romgrk/barbar.nvim',
  lazy = false,
  dependencies = {
    'lewis6991/gitsigns.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  init = function()
    vim.g.barbar_auto_setup = false
  end,
  opts = {
    animation = false,
  },
  keys = {
    { '[b', '<Cmd>BufferPrevious<CR>', desc = 'Previous Buffer' },
    { ']b', '<Cmd>BufferNext<CR>', desc = 'Next Buffer' },
    { '[B', '<Cmd>BufferMovePrevious<CR>', desc = 'Move Buffer to Previous' },
    { ']B', '<Cmd>BufferMoveNext<CR>', desc = 'Move Buffer to Next' },
    { ',b', '<Cmd>BufferClose<CR>', desc = 'Close Buffer' },
  },
}
