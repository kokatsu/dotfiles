-- vue_ls は TypeScript サポートのために vtsls を必要とする
-- vue-language-server 3.0.8 は @vue/typescript-plugin との互換性がないため、
-- globalPlugins は設定せず、vue_ls の組み込み TypeScript サポートを使用
local tsserver_filetypes = {
  'vue',
  'svelte',
}

---@type vim.lsp.Config
local vtsls_config = {
  workspace_required = true,
  root_dir = function(bufnr, on_dir)
    local root_markers = { 'package.json', 'tsconfig.json', 'jsconfig.json' }
    local project_root = vim.fs.root(bufnr, root_markers)
    on_dir(project_root)
  end,
  filetypes = tsserver_filetypes,
}

return vtsls_config
