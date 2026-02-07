-- https://github.com/folke/trouble.nvim

return {
  'folke/trouble.nvim',
  cmd = 'Trouble',
  opts = {
    auto_close = true,
    auto_preview = true,
    focus = true,
    follow = true,
    indent_guides = true,
    pinned = false,
    warn_no_results = true,
    open_no_results = false,
    icons = {
      indent = {
        fold_open = ' ',
        fold_closed = ' ',
      },
    },
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
      ['?'] = 'help',
      r = 'refresh',
      R = 'toggle_refresh',
      q = 'close',
      o = 'jump_close',
      ['<cr>'] = 'jump',
      ['<tab>'] = 'jump',
      ['<2-leftmouse>'] = 'jump',
      ['<c-x>'] = 'jump_split',
      ['<c-v>'] = 'jump_vsplit',
      p = 'preview',
      P = 'toggle_preview',
      i = 'inspect',
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
