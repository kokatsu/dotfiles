---@type vim.lsp.Config
return {
  cmd = { 'tsgo', '--lsp', '--stdio' },
  filetypes = {
    'javascript',
    'javascriptreact',
    'typescript',
    'typescriptreact',
  },
  workspace_required = true,
  root_dir = function(bufnr, on_dir)
    local tsgo_root_markers = {
      'tsconfig.json',
      'jsconfig.json',
      'package.json',
    }
    local deno_root_markers = {
      'deno.json',
      'deno.jsonc',
    }
    local project_root = vim.fs.root(bufnr, tsgo_root_markers)
    if not project_root or vim.fs.root(bufnr, deno_root_markers) then
      return
    end
    on_dir(project_root)
  end,
  single_file_support = false,
  settings = {
    typescript = {
      format = {
        enable = false,
      },
    },
  },
}
