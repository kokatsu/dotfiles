---@type vim.lsp.Config
local taplo_config = {
  settings = {
    evenBetterToml = {
      schema = {
        -- デフォルトの schemastore 全カタログ取得を無効化しメモリ消費を抑える。
        -- 必要なスキーマは下の associations で個別に対応付ける。
        catalogs = {},
        associations = {
          ['mise.local.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['mise.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['mise/config.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['.config/mise.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['.config/mise/config.toml'] = 'https://mise.jdx.dev/schema/mise.json',
          ['.typos.toml'] = 'https://raw.githubusercontent.com/crate-ci/typos/master/config.schema.json',
          ['stylua.toml'] = 'https://raw.githubusercontent.com/JohnnyMorganz/StyLua/main/stylua.schema.json',
          ['taplo.toml'] = 'https://www.schemastore.org/taplo.json',
        },
      },
    },
  },
}

return taplo_config
