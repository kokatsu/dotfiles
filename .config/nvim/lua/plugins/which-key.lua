-- https://github.com/folke/which-key.nvim

return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    preset = 'helix',
    spec = {
      -- Leader groups
      { '<leader>a', group = 'ai/sidekick' },
      { '<leader>c', group = 'code' },
      { '<leader>g', group = 'git' },
      { '<leader>o', group = 'octo (github)' },
      { '<leader>r', group = 'refactor' },
      { '<leader>t', group = 'typescript' },
      { '<leader>x', group = 'diagnostics' },
      { '<leader>y', group = 'yank' },
      -- Navigation groups
      { '[', group = 'prev' },
      { ']', group = 'next' },
      -- Surround group
      { 's', group = 'surround/flash' },
      -- Go to group
      { 'g', group = 'goto' },
      -- mini.surround descriptions
      { 'sa', desc = 'Add surrounding', mode = { 'n', 'x' } },
      { 'sd', desc = 'Delete surrounding' },
      { 'sr', desc = 'Replace surrounding' },
      { 'sf', desc = 'Find right surrounding' },
      { 'sF', desc = 'Find left surrounding' },
      { 'sh', desc = 'Highlight surrounding' },
      { 'sn', desc = 'Update n_lines' },
      -- mini.move descriptions
      { '<M-h>', desc = 'Move line/selection left', mode = { 'n', 'x' } },
      { '<M-j>', desc = 'Move line/selection down', mode = { 'n', 'x' } },
      { '<M-k>', desc = 'Move line/selection up', mode = { 'n', 'x' } },
      { '<M-l>', desc = 'Move line/selection right', mode = { 'n', 'x' } },
    },
  },
  keys = {
    {
      '<leader>?',
      function()
        require('which-key').show({ global = false })
      end,
      desc = 'Buffer Local Keymaps (which-key)',
    },
  },
}
