---@type vim.lsp.Config
local dockerls_config = {
  root_markers = {
    'Dockerfile',
    'compose.yaml',
    'compose.yml',
    'docker-bake.hcl',
  },
}

return dockerls_config
