-- https://github.com/neovim/nvim-lspconfig

return {
  'neovim/nvim-lspconfig',
  init = function()
    vim.diagnostic.config({
      virtual_text = true,
      severity_sort = true,
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = '󰅚 ',
          [vim.diagnostic.severity.WARN] = '󰀪 ',
          [vim.diagnostic.severity.HINT] = '󰌶 ',
          [vim.diagnostic.severity.INFO] = ' ',
        },
        linehl = {
          [vim.diagnostic.severity.ERROR] = 'DiagnosticErrorLine',
          [vim.diagnostic.severity.WARN] = 'DiagnosticWarnLine',
          [vim.diagnostic.severity.HINT] = 'DiagnosticHintLine',
          [vim.diagnostic.severity.INFO] = 'DiagnosticInfoLine',
        },
      },
    })
  end,
  config = function()
    vim.diagnostic.config({
      virtual_lines = true,
      update_in_insert = false,
    })
    vim.lsp.inlay_hint.enable()
    vim.lsp.enable({
      'biome',
      'cssmodules_ls',
      'denols',
      'dockerls',
      'jsonls',
      'html',
      'lua_ls',
      'postgres_lsp',
      'ruby_lsp',
      'svelte',
      'tailwindcss',
      'taplo',
      'unocss',
      'vtsls',
      'vue_ls',
      'yamlls',
    })
  end,
}
