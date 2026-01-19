---@type vim.lsp.Config
local vue_ls_config = {
  init_options = {
    vue = {
      -- Hybrid Mode: vtsls が TypeScript を処理、vue_ls はテンプレートのみ
      -- false にすると vue_ls が全て処理（より安定）
      hybridMode = false,
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
  -- ルートディレクトリの判定
  root_dir = function(bufnr, on_dir)
    local root_markers = { 'vue.config.js', 'vue.config.ts', 'nuxt.config.js', 'nuxt.config.ts', 'package.json' }
    local project_root = vim.fs.root(bufnr, root_markers)
    on_dir(project_root)
  end,
}

return vue_ls_config
