---@type vim.lsp.Config
local biome_config = {
  filetypes = {
    'json',
    'jsonc',
    'javascript',
    'javascriptreact',
    'svelte',
    'typescript',
    'typescriptreact',
    'vue',
  },
  root_markers = {
    '.biome.json',
    '.biome.jsonc',
    'biome.json',
    'biome.jsonc',
  },
}

return biome_config
