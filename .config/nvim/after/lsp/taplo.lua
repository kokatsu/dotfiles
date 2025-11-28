---@type vim.lsp.Config
local taplo_config = {
  settings = {
    evenBetterToml = {
      schema = {
        associations = {
          ['mise.local.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['mise.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['mise/config.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['.config/mise.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['.config/mise/config.toml'] = 'https://mise.jdx.dev/schema/mise.json',
        },
      },
    },
  },
}

return taplo_config
