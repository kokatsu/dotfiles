---@type vim.lsp.Config
local vue_ls_config = {
  on_init = function(client)
    ---@param _ lsp.ResponseError
    ---@param result any
    ---@param context lsp.HandlerContext
    local function typescriptHandler(_, result, context)
      local ts_client = vim.lsp.get_clients({ bufnr = context.bufnr, name = 'ts_ls' })[1]
        or vim.lsp.get_clients({ bufnr = context.bufnr, name = 'vtsls' })[1]
        or vim.lsp.get_clients({ bufnr = context.bufnr, name = 'typescript-tools' })[1]

      if not ts_client then
        -- typescript-tools の起動を待つ（最大5秒）
        vim.defer_fn(function()
          typescriptHandler(_, result, context)
        end, 200)
        return
      end

      local param = unpack(result)
      local id, command, payload = unpack(param)
      ts_client:exec_cmd({
        title = 'vue_request_forward',
        command = 'typescript.tsserverRequest',
        arguments = {
          command,
          payload,
        },
      }, { bufnr = context.bufnr }, function(_, r)
        local response_data = { { id, r and r.body } }
        ---@diagnostic disable-next-line: param-type-mismatch
        client:notify('tsserver/response', response_data)
      end)
    end

    client.handlers['tsserver/request'] = typescriptHandler
  end,
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
  -- ルートディレクトリの判定
  root_dir = function(bufnr, on_dir)
    local root_markers = { 'vue.config.js', 'vue.config.ts', 'nuxt.config.js', 'nuxt.config.ts', 'package.json' }
    local project_root = vim.fs.root(bufnr, root_markers)
    on_dir(project_root)
  end,
}

return vue_ls_config
