-- https://github.com/folke/trouble.nvim

return {
  'folke/trouble.nvim',
  cmd = 'Trouble',
  opts = {
    auto_close = true,
    focus = true,
    modes = {
      cascade = {
        mode = 'diagnostics',
        filter = { buf = 0 },
        groups = {
          { 'filename', format = '{file_icon} {basename} {count}' },
        },
      },
      lsp_references = {
        mode = 'lsp_references',
        auto_preview = true,
        auto_refresh = true,
      },
    },
    keys = {
      ['<tab>'] = 'jump',
      ['<c-x>'] = 'jump_split',
    },
  },
  keys = {
    { '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', desc = 'Diagnostics (Trouble)' },
    { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', desc = 'Buffer Diagnostics (Trouble)' },
    { '<leader>xs', '<cmd>Trouble symbols toggle focus=false<cr>', desc = 'Symbols (Trouble)' },
    {
      '<leader>xl',
      '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
      desc = 'LSP Definitions / references (Trouble)',
    },
    { '<leader>xL', '<cmd>Trouble loclist toggle<cr>', desc = 'Location List (Trouble)' },
    { '<leader>xQ', '<cmd>Trouble qflist toggle<cr>', desc = 'Quickfix List (Trouble)' },
    { '<leader>xc', '<cmd>Trouble cascade toggle<cr>', desc = 'Cascade Diagnostics (Trouble)' },
    {
      ']d',
      function()
        require('trouble').next({ skip_groups = true, jump = true })
      end,
      desc = 'Next diagnostic (Trouble)',
    },
    {
      '[d',
      function()
        require('trouble').prev({ skip_groups = true, jump = true })
      end,
      desc = 'Previous diagnostic (Trouble)',
    },
  },
}
