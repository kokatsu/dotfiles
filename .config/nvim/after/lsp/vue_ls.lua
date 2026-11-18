---@type vim.lsp.Config
local vue_ls_config = {
  root_markers = { { 'vue.config.js', 'vue.config.ts', 'nuxt.config.js', 'nuxt.config.ts', 'package.json' } },
  init_options = {
    vue = {
      -- Hybrid Mode: typescript-tools が TypeScript を処理、vue_ls はテンプレート/CSS のみ
      hybridMode = true,
    },
    typescript = {
      -- プロジェクトの TypeScript を優先、なければグローバルを使用
      tsdk = '',
    },
  },
  settings = {
    vue = {
      complete = {
        casing = {
          -- コンポーネントタグ: kebab-case (例: <my-component>)
          tags = 'kebab',
          -- props: camelCase (例: :myProp)
          props = 'camel',
        },
      },
      autoInsert = {
        -- .value の自動挿入 (ref)
        dotValue = true,
        -- 閉じタグを自動挿入
        bracketSpacing = true,
      },
      inlayHints = {
        -- インレイヒントの設定
        missingProps = true,
        inlineHandlerLeading = true,
        optionsWrapper = true,
      },
      codeActions = {
        -- extract 系のコードアクションを有効化
        enabled = true,
        savingTimeLimit = 2000,
      },
    },
  },
}

return vue_ls_config
