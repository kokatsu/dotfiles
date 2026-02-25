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
          ['.typos.toml'] = 'https://raw.githubusercontent.com/crate-ci/typos/master/config.schema.json',
          ['stylua.toml'] = 'https://raw.githubusercontent.com/JohnnyMorganz/StyLua/main/stylua.schema.json',
          ['taplo.toml'] = 'https://www.schemastore.org/taplo.json',
          ['termframe/config.toml'] = 'https://raw.githubusercontent.com/pamburus/termframe/main/schema/json/config.schema.json',
        },
      },
    },
  },
}

return taplo_config
