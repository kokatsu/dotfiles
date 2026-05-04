-- https://github.com/kokatsu/typescript-tools.nvim

-- Nix store prefix を抽出 (例: /nix/store/<hash>-<name>)
local function nix_store_prefix(bin_name)
  local bin = vim.fn.exepath(bin_name)
  if bin == '' then
    return nil
  end
  return vim.fn.resolve(bin):match('(/nix/store/[^/]+)')
end

-- bundled package を再帰 glob で検出する
local function glob_first(prefix, pattern)
  if not prefix then
    return nil
  end
  local matches = vim.fn.glob(prefix .. '/' .. pattern, false, true)
  if type(matches) == 'table' and #matches > 0 then
    return matches[1]
  end
  return nil
end

-- vtsls にバンドルされた tsserver.js を検出
local function find_tsserver_path()
  return glob_first(nix_store_prefix('vtsls'), 'lib/**/typescript/lib/tsserver.js')
end

-- vue-language-server にバンドルされた @vue/typescript-plugin を検出
local function find_vue_typescript_plugin()
  return glob_first(nix_store_prefix('vue-language-server'), 'lib/**/@vue/typescript-plugin')
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
    { '<leader>lo', '<cmd>TSToolsOrganizeImports<cr>', desc = 'Organize imports' },
    { '<leader>la', '<cmd>TSToolsAddMissingImports<cr>', desc = 'Add missing imports' },
    { '<leader>lu', '<cmd>TSToolsRemoveUnused<cr>', desc = 'Remove unused' },
    { '<leader>lF', '<cmd>TSToolsFixAll<cr>', desc = 'Fix all' },
    { '<leader>ld', '<cmd>TSToolsGoToSourceDefinition<cr>', desc = 'Go to source definition' },
    { '<leader>lR', '<cmd>TSToolsRenameFile<cr>', desc = 'Rename file' },
    { '<leader>lf', '<cmd>TSToolsFileReferences<cr>', desc = 'File references' },
  },
  -- opts は function 化して lazy load (ft イベント) 時に評価する
  -- spec 構築時 (startup 直後) の vim.fn.exepath は PATH や nix-profile symlink の状態に
  -- 影響されて nil を返すことがあったため、評価タイミングを後ろ倒しする
  opts = function()
    local tsserver_path = find_tsserver_path()
    local vue_plugin_path = find_vue_typescript_plugin()
    if not tsserver_path then
      vim.notify('typescript-tools: tsserver.js not found in vtsls Nix store', vim.log.levels.WARN)
    end
    return {
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
        tsserver_path = tsserver_path,
        expose_as_code_action = 'all',
        complete_function_calls = true,
        tsserver_plugins = {
          {
            name = '@vue/typescript-plugin',
            location = vue_plugin_path,
            languages = { 'vue' },
          },
        },
      },
      root_dir = function(bufnr, on_dir)
        -- Don't start for Deno files (check shebang)
        if vim.b[bufnr].is_deno then
          return
        end

        -- Only start if package.json or tsconfig.json exists,
        -- and skip when a Deno project marker is present (denols handles it)
        local root = vim.fs.root(bufnr, { 'package.json', 'tsconfig.json', 'jsconfig.json' })
        if not root or vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc' }) then
          return
        end
        on_dir(root)
      end,
    }
  end,
}
