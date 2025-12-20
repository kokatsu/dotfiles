---@type vim.lsp.Config
local denols_config = {
  cmd = { 'deno', 'lsp' },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
  root_dir = function(bufnr, on_dir)
    -- If shebang indicates deno, start LSP unconditionally
    if vim.b[bufnr].is_deno then
      local file_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':h')
      on_dir(file_dir)
      return
    end

    local deno_root_markers = {
      'deno.json',
      'deno.jsonc',
    }
    local tsgo_root_markers = {
      'tsconfig.json',
      'jsconfig.json',
      'package.json',
    }
    local project_root = vim.fs.root(bufnr, deno_root_markers)
    if not project_root or vim.fs.root(bufnr, tsgo_root_markers) then
      return
    end
    on_dir(project_root)
  end,
  single_file_support = true,
}

return denols_config
