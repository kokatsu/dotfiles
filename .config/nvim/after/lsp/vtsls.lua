-- vue_ls は hybridMode = false で独自に TypeScript を処理するため、
-- vtsls は vue ファイルタイプを除外
-- Svelte は svelte-language-server が TypeScript を処理
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
