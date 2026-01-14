-- https://github.com/folke/sidekick.nvim
-- AI sidekick for Neovim with Next Edit Suggestions

return {
  'folke/sidekick.nvim',
  opts = {
    cli = {
      mux = {
        backend = 'zellij',
        enabled = true,
      },
    },
  },
  keys = {
    {
      '<tab>',
      function()
        if not require('sidekick').nes_jump_or_apply() then
          return '<Tab>'
        end
      end,
      expr = true,
      desc = 'Goto/Apply Next Edit Suggestion',
    },
    {
      '<s-tab>',
      function()
        require('sidekick').nes_jump(-1)
      end,
      desc = 'Prev Edit Suggestion',
    },
    {
      '<leader>an',
      '<cmd>Sidekick nes show<cr>',
      desc = 'Sidekick NES',
    },
    {
      '<leader>as',
      '<cmd>Sidekick cli select<cr>',
      desc = 'Sidekick Select CLI',
    },
    {
      '<leader>ac',
      '<cmd>Sidekick cli show name=claude focus=true<cr>',
      desc = 'Sidekick Claude',
    },
    {
      '<leader>ap',
      '<cmd>Sidekick cli show name=copilot focus=true<cr>',
      desc = 'Sidekick Copilot',
    },
    {
      '<leader>at',
      '<cmd>Sidekick cli toggle<cr>',
      desc = 'Sidekick Toggle',
    },
  },
}
