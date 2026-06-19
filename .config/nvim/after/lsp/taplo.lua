-- Taplo はワークスペース索引/スキーマ取得でメモリが暴走することがあり、
-- swap=0 の WSL では カーネル OOM が VM ごと巻き込んで落ちる。
-- Linux (systemd) ではメモリ上限付きの transient scope (cgroup v2) で起動し、
-- 上限超過時に Taplo だけを OOM kill して VM を守る。
-- systemd-run が無い環境 (macOS 等) では素の cmd にフォールバックする。
local cmd = { 'taplo', 'lsp', 'stdio' }
if vim.fn.executable('systemd-run') == 1 then
  cmd = {
    'systemd-run',
    '--user',
    '--scope',
    '--quiet',
    '--collect',
    '-p',
    'MemoryMax=2G',
    '-p',
    'MemorySwapMax=0',
    'taplo',
    'lsp',
    'stdio',
  }
end

---@type vim.lsp.Config
local taplo_config = {
  cmd = cmd,
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
