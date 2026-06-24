-- Ruby LSP 設定
-- https://shopify.github.io/ruby-lsp/editors.html

---@type vim.lsp.Config
local ruby_lsp_config = {
  -- BUNDLE_GEMFILE=. で bundler セットアップをスキップし直接起動。
  -- root_dir を cwd に渡し、モノレポ内の各サブプロジェクトを正しく認識させる。
  cmd = function(dispatchers, config)
    return vim.lsp.rpc.start(
      { 'env', 'BUNDLE_GEMFILE=.', 'ruby-lsp' },
      dispatchers,
      config and config.root_dir and { cwd = config.cmd_cwd or config.root_dir }
    )
  end,
  root_markers = { 'Gemfile', '.git' },
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

  -- root_dir が異なるサブプロジェクトには別クライアントを起動
  reuse_client = function(client, config)
    config.cmd_cwd = config.root_dir
    return client.name == config.name and client.config.root_dir == config.root_dir
  end,

  -- LSPアタッチ時のコールバック
  on_attach = function(client, bufnr)
    -- CodeLens自動更新
    if client:supports_method('textDocument/codeLens', bufnr) then
      vim.lsp.codelens.enable(true, { bufnr = bufnr })
    end
  end,
}

return ruby_lsp_config
