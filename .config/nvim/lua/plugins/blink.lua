-- https://github.com/Saghen/blink.cmp

return {
  name = 'blink.cmp',
  dir = vim.fn.stdpath('data') .. '/nix-plugins/blink.cmp',
  -- nvim-lspconfig.lua が起動時に get_lsp_capabilities() を要求するため遅延できない
  lazy = false,
  -- mini.snippets は mini.nvim 同梱版を使うため依存に含めない
  dependencies = {
    'rafamadriz/friendly-snippets',
    'moyiz/blink-emoji.nvim',
  },

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    keymap = {
      preset = 'super-tab',
      ['<C-l>'] = { 'show', 'show_documentation', 'hide_documentation' },
      -- editor.lua の日付挿入 (insert mode <C-k>) を優先するため blink の signature toggle を解除
      ['<C-k>'] = {},
      -- 補完確定は <Tab> (super-tab) と <C-y>。CR は nvim-autopairs の括弧改行に委譲する
      ['<CR>'] = { 'fallback' },
    },

    appearance = {
      nerd_font_variant = 'mono',
    },

    completion = {
      menu = { auto_show = true },
      documentation = { auto_show = true, auto_show_delay_ms = 200 },
    },

    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer', 'emoji' },
      providers = {
        emoji = {
          module = 'blink-emoji',
          name = 'Emoji',
          score_offset = 15,
          opts = { insert = true },
        },
      },
    },

    fuzzy = {
      implementation = 'rust',
      prebuilt_binaries = { download = false },
    },

    snippets = { preset = 'mini_snippets' },
  },
  opts_extend = { 'sources.default' },
}
