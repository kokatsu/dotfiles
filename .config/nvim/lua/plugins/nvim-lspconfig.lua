-- https://github.com/neovim/nvim-lspconfig

return {
  'neovim/nvim-lspconfig',
  init = function()
    vim.diagnostic.config({
      virtual_text = {
        format = function(diagnostic)
          if diagnostic.source then
            return string.format('[%s] %s', diagnostic.source, diagnostic.message)
          end
          return diagnostic.message
        end,
      },
      severity_sort = true,
      update_in_insert = false,
      float = {
        format = function(diagnostic)
          if diagnostic.source then
            return string.format('[%s] %s', diagnostic.source, diagnostic.message)
          end
          return diagnostic.message
        end,
      },
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
    -- Set default capabilities for all LSP clients to use the same position encoding
    vim.lsp.config('*', {
      capabilities = require('blink.cmp').get_lsp_capabilities({
        general = {
          positionEncodings = { 'utf-16' },
        },
      }),
    })

    vim.lsp.inlay_hint.enable()

    local servers = {
      'bashls',
      'biome',
      'cssmodules_ls',
      'denols',
      'dockerls',
      'eslint',
      'html',
      'jsonls',
      'kakehashi',
      'lua_ls',
      'markdown_oxide',
      'nixd',
      'postgres_lsp',
      'serve_d',
      'svelte',
      'tailwindcss',
      'taplo',
      'unocss',
      'vtsls',
      'vue_ls',
      'vue_ls_legacy',
      'yamlls',
      'zls',
    }

    -- Conditionally enable ruby_lsp if executable
    if vim.fn.executable('ruby-lsp') == 1 then
      table.insert(servers, 'ruby_lsp')
    end

    vim.lsp.enable(servers)
  end,
}
