-- https://github.com/atusy/kakehashi
-- Tree-sitter based Language Server for embedded code blocks

---@type vim.lsp.Config
return {
  filetypes = { 'markdown' },
  init_options = {
    autoInstall = true,
    -- LSP Bridge: Markdown内の埋め込みコードブロックで各言語のLSP機能を有効化
    languageServers = {
      -- TypeScript/JavaScript
      vtsls = {
        cmd = { 'vtsls', '--stdio' },
        languages = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' },
      },
      -- Lua
      lua_ls = {
        cmd = { 'lua-language-server' },
        languages = { 'lua' },
      },
      -- Rust
      rust_analyzer = {
        cmd = { 'rust-analyzer' },
        languages = { 'rust' },
      },
      -- Nix
      nixd = {
        cmd = { 'nixd' },
        languages = { 'nix' },
      },
      -- SQL (PostgreSQL)
      postgres_lsp = {
        cmd = { 'postgres_lsp' },
        languages = { 'sql' },
      },
      -- Vue
      vue_ls = {
        cmd = { 'vue-language-server', '--stdio' },
        languages = { 'vue' },
      },
    },
    -- Markdown内で有効にするブリッジ言語
    languages = {
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
  on_attach = function(_, bufnr)
    -- kakehashiがアタッチされたバッファでTree-sitterハイライトを無効化
    -- (LSP semantic tokensと競合するため)
    vim.treesitter.stop(bufnr)
  end,
}
