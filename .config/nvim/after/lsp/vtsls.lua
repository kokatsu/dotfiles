-- vue ファイルの TypeScript は typescript-tools が担当する (vue_ls は hybridMode = true で
-- テンプレート/CSS のみ) ため vtsls は vue を持たない。svelte だけ vtsls に任せる
local tsserver_filetypes = {
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
