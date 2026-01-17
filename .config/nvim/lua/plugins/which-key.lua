-- https://github.com/folke/which-key.nvim

return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    preset = 'helix',
    spec = {
      { '<leader>c', group = 'code' },
      { '<leader>g', group = 'git' },
      { '<leader>r', group = 'refactor' },
      { '<leader>s', group = 'swap/search' },
      { '<leader>t', group = 'test' },
      { '<leader>x', group = 'diagnostics' },
      { '<leader>y', group = 'yank' },
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
