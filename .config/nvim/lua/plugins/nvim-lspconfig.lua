-- https://github.com/neovim/nvim-lspconfig

return {
  'neovim/nvim-lspconfig',
  init = function()
    vim.diagnostic.config({
      virtual_text = true,
      virtual_lines = false,
      severity_sort = true,
      update_in_insert = false,
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
    vim.lsp.inlay_hint.enable()

    -- :LspInfo command (removed in nvim-lspconfig 2024)
    vim.api.nvim_create_user_command('LspInfo', function()
      -- https://github.com/neovim/nvim-lspconfig/commit/eefb0030c7c5f795ed2b1b0cd498d2670d7513f8
      if vim.fn.has('nvim-0.12') == 1 then
        vim.cmd('checkhealth vim.lsp')
        return
      end
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      if #clients == 0 then
        print('No LSP clients attached to this buffer')
        return
      end
      for _, client in ipairs(clients) do
        print(string.format('[%d] %s (root: %s)', client.id, client.name, client.root_dir or 'none'))
      end
    end, { desc = 'Show LSP clients attached to current buffer' })

    vim.api.nvim_create_user_command('LspRestart', function()
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      for _, client in ipairs(clients) do
        local name = client.name
        client:stop()
        vim.defer_fn(function()
          vim.cmd('edit')
        end, 100)
        print('Restarting ' .. name .. '...')
      end
    end, { desc = 'Restart LSP clients attached to current buffer' })

    vim.lsp.enable({
      'biome',
      'cssmodules_ls',
      'denols',
      'dockerls',
      'eslint',
      'gh_actions_ls',
      'html',
      'jsonls',
      'lua_ls',
      'nixd',
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
