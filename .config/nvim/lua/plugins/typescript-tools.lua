-- https://github.com/pmizio/typescript-tools.nvim

return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  ft = {
    'javascript',
    'javascriptreact',
    'typescript',
    'typescriptreact',
  },
  opts = {
    expose_as_code_action = 'all',
    complete_function_calls = true,
    include_completions_with_insert_text = true,
    single_file_support = false,
    root_dir = function(fname)
      -- Don't start for Deno files (check shebang)
      local bufnr = vim.fn.bufnr(fname)
      if bufnr ~= -1 and vim.b[bufnr].is_deno then
        return nil
      end

      -- Only start if package.json or tsconfig.json exists
      local util = require('lspconfig.util')
      return util.root_pattern('package.json', 'tsconfig.json', 'jsconfig.json')(fname)
    end,
  },
}
