-- https://github.com/atusy/kakehashi
-- Tree-sitter based Language Server for embedded code blocks

---@type vim.lsp.Config
return {
  filetypes = { 'markdown' },
  on_attach = function(_, bufnr)
    -- kakehashi の semantic tokens を Markdown のハイライト元にして、
    -- nvim-treesitter との二重ハイライトを避ける。
    vim.api.nvim_create_autocmd('LspTokenUpdate', {
      buffer = bufnr,
      once = true,
      callback = function()
        vim.bo[bufnr].syntax = 'OFF'
        vim.treesitter.stop(bufnr)
      end,
    })
  end,
  init_options = {
    -- LSP Bridge: Markdown内の埋め込みコードブロックで各言語のLSP機能を有効化
    languageServers = {
      -- TypeScript/JavaScript
      vtsls = {
        cmd = { 'vtsls', '--stdio' },
        languages = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' },
        workspaceMarkers = { { 'tsconfig.json', 'jsconfig.json', 'package.json' }, '.git' },
      },
      -- Lua
      lua_ls = {
        cmd = { 'lua-language-server' },
        languages = { 'lua' },
        workspaceMarkers = { { '.luarc.json', '.luarc.jsonc', 'stylua.toml' }, '.git' },
      },
      -- Rust
      rust_analyzer = {
        cmd = { 'rust-analyzer' },
        languages = { 'rust' },
        workspaceMarkers = { 'Cargo.toml', '.git' },
      },
      -- Nix
      nixd = {
        cmd = { 'nixd' },
        languages = { 'nix' },
        workspaceMarkers = { 'flake.nix', '.git' },
      },
      -- SQL (PostgreSQL)
      postgres_lsp = {
        cmd = { 'postgres-language-server', 'lsp-proxy' },
        languages = { 'sql' },
        workspaceMarkers = { { 'postgres-language-server.toml', 'package.json' }, '.git' },
      },
      -- Vue
      vue_ls = {
        cmd = { 'vue-language-server', '--stdio' },
        languages = { 'vue' },
        workspaceMarkers = {
          { 'vue.config.js', 'vue.config.ts', 'nuxt.config.js', 'nuxt.config.ts', 'package.json' },
          '.git',
        },
      },
    },
    languages = {
      -- 不足パーサー/クエリの自動インストール (ワイルドカード既定)
      _ = { autoInstall = true },
      -- Markdown内で有効にするブリッジ言語
      markdown = {
        bridge = {
          typescript = { enabled = true },
          javascript = { enabled = true },
          typescriptreact = { enabled = true },
          javascriptreact = { enabled = true },
          lua = { enabled = true },
          rust = { enabled = true },
          nix = { enabled = true },
          sql = { enabled = true },
          vue = { enabled = true },
        },
      },
    },
  },
}
