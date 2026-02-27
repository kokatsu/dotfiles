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
  keys = {
    { '<leader>to', '<cmd>TSToolsOrganizeImports<cr>', desc = 'Organize imports' },
    { '<leader>ta', '<cmd>TSToolsAddMissingImports<cr>', desc = 'Add missing imports' },
    { '<leader>tr', '<cmd>TSToolsRemoveUnused<cr>', desc = 'Remove unused' },
    { '<leader>tF', '<cmd>TSToolsFixAll<cr>', desc = 'Fix all' },
    { '<leader>td', '<cmd>TSToolsGoToSourceDefinition<cr>', desc = 'Go to source definition' },
    { '<leader>tR', '<cmd>TSToolsRenameFile<cr>', desc = 'Rename file' },
    { '<leader>tf', '<cmd>TSToolsFileReferences<cr>', desc = 'File references' },
  },
  opts = {
    -- Override default filetypes to fix checkhealth warnings
    -- (plugin defaults include invalid 'javascript.jsx' and 'typescript.tsx')
    filetypes = {
      'javascript',
      'javascriptreact',
      'typescript',
      'typescriptreact',
    },
    expose_as_code_action = 'all',
    complete_function_calls = true,
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
