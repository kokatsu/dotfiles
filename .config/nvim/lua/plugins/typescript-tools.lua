-- https://github.com/kokatsu/typescript-tools.nvim

-- Nix 環境: バイナリの実パスから Nix ストアプレフィックスを取得
local function nix_store_prefix(bin_name)
  local bin = vim.fn.exepath(bin_name)
  if bin == '' then
    return nil
  end
  return vim.fn.resolve(bin):match('(/nix/store/[^/]+)')
end

-- vtsls にバンドルされた tsserver.js を検出
local function find_tsserver_path()
  local prefix = nix_store_prefix('vtsls')
  if not prefix then
    return nil
  end
  local found = vim.fn.glob(prefix .. '/lib/*/node_modules/.pnpm/typescript@*/node_modules/typescript/lib/tsserver.js')
  if found ~= '' then
    return found:match('[^\n]+')
  end
  return nil
end

-- vue-language-server にバンドルされた @vue/typescript-plugin を検出
local function find_vue_typescript_plugin()
  local prefix = nix_store_prefix('vue-language-server')
  if not prefix then
    return nil
  end
  local found = vim.fn.glob(prefix .. '/lib/*/node_modules/.pnpm/node_modules/@vue/typescript-plugin')
  if found ~= '' then
    return found:match('[^\n]+')
  end
  return nil
end

return {
  'kokatsu/typescript-tools.nvim',
  branch = 'feat/tsserver-plugins-location-languages',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  ft = {
    'javascript',
    'javascriptreact',
    'typescript',
    'typescriptreact',
    'vue',
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
      'vue',
    },
    single_file_support = false,
    settings = {
      tsserver_path = find_tsserver_path(),
      expose_as_code_action = 'all',
      complete_function_calls = true,
      tsserver_plugins = {
        {
          name = '@vue/typescript-plugin',
          location = find_vue_typescript_plugin(),
          languages = { 'vue' },
        },
      },
    },
    root_dir = function(bufnr, on_dir)
      -- Don't start for Deno files (check shebang)
      if vim.b[bufnr].is_deno then
        return
      end

      -- Only start if package.json or tsconfig.json exists
      local root = vim.fs.root(bufnr, { 'package.json', 'tsconfig.json', 'jsconfig.json' })
      on_dir(root)
    end,
  },
}
