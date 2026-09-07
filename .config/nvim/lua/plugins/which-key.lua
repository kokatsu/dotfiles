-- https://github.com/folke/which-key.nvim

return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    preset = 'helix',
    spec = {
      -- Leader groups
      { '<leader>c', group = 'code/lsp' },
      { '<leader>g', group = 'git' },
      { '<leader>l', group = 'language' },
      { '<leader>o', group = 'octo (github)' },
      { '<leader>t', group = 'toggle' },
      { '<leader>x', group = 'diagnostics' },
      { '<leader>y', group = 'yank' },
      -- Navigation groups
      { '[', group = 'prev' },
      { ']', group = 'next' },
      -- Surround group
      { 's', group = 'surround' },
      -- FFF group
      { '<leader>F', group = 'fff' },
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
