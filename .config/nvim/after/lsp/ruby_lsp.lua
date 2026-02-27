-- Ruby LSP 設定
-- https://shopify.github.io/ruby-lsp/editors.html

---@type vim.lsp.Config
local ruby_lsp_config = {
  -- Docker環境のプロジェクトではホスト上で bundle install が成功しないため
  -- BUNDLE_GEMFILE を設定して bundler セットアップをスキップし直接起動
  cmd = { 'env', 'BUNDLE_GEMFILE=.', 'ruby-lsp' },
  init_options = {
    -- フォーマッタ設定 ('auto', 'rubocop', 'standard', 'syntax_tree')
    formatter = 'auto',

    -- リンター設定
    linters = { 'rubocop' },

    -- 実験的機能を有効化
    experimentalFeaturesEnabled = true,

    -- 有効にする機能
    enabledFeatures = {
      codeActions = true,
      codeLens = true, -- テスト実行、ファイルジャンプ等
      completion = true,
      diagnostics = true,
      documentHighlights = true,
      documentLink = true,
      documentSymbols = true,
      foldingRanges = true,
      formatting = true,
      hover = true,
      inlayHint = true,
      onTypeFormatting = true,
      selectionRanges = true,
      semanticHighlighting = true,
      signatureHelp = true,
      typeHierarchy = true,
      workspaceSymbol = true,
    },

    -- Inlay Hint詳細設定
    featuresConfiguration = {
      inlayHint = {
        implicitHashValue = true, -- { key: } → { key: key }
        implicitRescue = true, -- rescue → rescue StandardError
      },
    },

    -- Rails用アドオン設定
    addonSettings = {
      ['Ruby LSP Rails'] = {
        enablePendingMigrationsPrompt = true,
      },
    },
  },

  -- LSPアタッチ時のコールバック
  on_attach = function(client, bufnr)
    -- CodeLens自動更新
    if client:supports_method('textDocument/codeLens', bufnr) then
      vim.api.nvim_create_autocmd({ 'BufEnter', 'InsertLeave', 'BufWritePost' }, {
        buffer = bufnr,
        callback = function()
          vim.lsp.codelens.refresh({ bufnr = bufnr })
        end,
        desc = 'Ruby LSP: Refresh CodeLens',
      })
      -- 初回リフレッシュ
      vim.lsp.codelens.refresh({ bufnr = bufnr })
    end
  end,
}

return ruby_lsp_config
