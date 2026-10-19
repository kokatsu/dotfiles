-- https://github.com/folke/noice.nvim

return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  dependencies = {
    'MunifTanjim/nui.nvim',
  },
  opts = {
    lsp = {
      override = {
        ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
        ['vim.lsp.util.stylize_markdown'] = true,
      },
      progress = {
        throttle = 1000 / 30,
      },
    },
    notify = { enabled = false },
    presets = {
      command_palette = true,
      lsp_doc_border = true,
    },
    views = {
      cmdline_popup = {
        position = { row = '50%', col = '50%' },
        size = { width = 60, height = 'auto' },
      },
      mini = {
        win_options = {
          winblend = 0,
        },
      },
    },
    routes = {
      {
        filter = {
          event = 'msg_show',
          kind = '',
          find = 'written',
        },
        opts = { skip = true },
      },
      {
        view = 'notify',
        filter = { event = 'msg_showmode' },
      },
      {
        filter = {
          event = 'msg_show',
          min_height = 10,
        },
        view = 'split',
      },
    },
  },
}
