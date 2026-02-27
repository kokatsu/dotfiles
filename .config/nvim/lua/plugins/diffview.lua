-- https://github.com/sindrets/diffview.nvim

return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory', 'DiffviewClose' },
  keys = {
    { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = 'Git Diff View' },
    { '<leader>gD', '<cmd>DiffviewOpen main...HEAD<cr>', desc = 'Diff vs main' },
    { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = 'File History' },
    { '<leader>gH', '<cmd>DiffviewFileHistory<cr>', desc = 'Branch History' },
    { '<leader>gq', '<cmd>DiffviewClose<cr>', desc = 'Close Diff View' },
  },
  opts = {
    enhanced_diff_hl = true,
    view = {
      merge_tool = {
        layout = 'diff3_mixed',
      },
    },
    keymaps = {
      view = {
        { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close' } },
      },
      file_panel = {
        { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close' } },
      },
      file_history_panel = {
        { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close' } },
      },
    },
  },
}
