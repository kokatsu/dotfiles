---@type vim.lsp.Config
local biome_config = {
  filetypes = {
    'json',
    'jsonc',
    'javascript',
    'javascriptreact',
    'typescript',
    'typescriptreact',
    'vue',
  },
  root_markers = {
    'biome.json',
    'biome.jsonc',
  },
}

return biome_config
