-- https://github.com/atusy/kakehashi
-- Tree-sitter based Language Server for embedded code blocks

---@type vim.lsp.Config
return {
  filetypes = { 'markdown' },
  on_attach = function(_, bufnr)
    local function use_semantic_highlighting()
      vim.treesitter.stop(bufnr)
      -- Tree-sitter の停止は syntax を再設定するため、その後で無効にする。
      vim.bo[bufnr].syntax = 'OFF'
      -- Tree-sitter の稼働中に有効にすると、highlights.scm の conceal でフェンス行や ``` まで隠れる
      for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        vim.wo[win][0].conceallevel = 2
      end
    end

    -- kakehashi の semantic tokens を Markdown のハイライト元にして、
    -- nvim-treesitter との二重ハイライトを避ける。
    vim.api.nvim_create_autocmd('LspTokenUpdate', {
      buffer = bufnr,
      once = true,
      callback = function()
        use_semantic_highlighting()
        -- 外部編集後の再読み込みで FileType が Tree-sitter ハイライトを再開するため、再度停止する。
        vim.api.nvim_create_autocmd('FileChangedShellPost', {
          buffer = bufnr,
          callback = use_semantic_highlighting,
        })
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
      -- after/queries/markdown/injections.scm の console → bash は kakehashi には効かない
      console = { base = 'bash' },
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
    features = {
      ['textDocument/semanticTokens'] = {
        captureMappings = {
          -- 既定の string のままだとフェンス行や埋め込みコードの文字列と区別できない。
          -- 独自のトークン種別は legend 外で描画されないため、修飾子で区別する
          markdown_inline = { ['markup.raw'] = 'string.documentation' },
        },
      },
    },
  },
}
