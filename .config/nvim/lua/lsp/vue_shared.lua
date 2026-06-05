-- Vue language server の共有設定。
-- vue_ls (Vue 3, 最新 3.2.9) と vue_ls_legacy (Vue 2, 3.0.x) で
-- on_init ハンドラ・init_options・settings を共有する。
-- 3.0/3.2 とも v3 系プロトコル (named pipe 廃止、tsserver/request を
-- クライアント側で typescript-tools へ転送) なので on_init は共通で使える。

local M = {}

-- ルートディレクトリ判定用マーカー
M.root_markers = { 'vue.config.js', 'vue.config.ts', 'nuxt.config.js', 'nuxt.config.ts', 'package.json' }

-- バッファ上方の package.json を辿り、最初に vue 依存を宣言したものの
-- メジャーバージョンを返す。見つからなければ nil。
-- 例: vue ^2.7 のプロジェクト → 2 / vue 3.x のプロジェクト → 3
function M.vue_major(bufnr)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local dir = fname ~= '' and vim.fs.dirname(fname) or vim.fn.getcwd()
  for _, pkg in ipairs(vim.fs.find('package.json', { upward = true, path = dir, limit = math.huge })) do
    local ok, json = pcall(vim.json.decode, table.concat(vim.fn.readfile(pkg), '\n'))
    if ok then
      local v = (json.dependencies or {}).vue or (json.devDependencies or {}).vue
      if v then
        return tonumber(tostring(v):match('(%d+)'))
      end
    end
  end
end

-- root_dir を生成するヘルパー。predicate(major) が true のプロジェクトでのみ
-- on_dir を呼ぶ（= attach する）。vue_ls と vue_ls_legacy は同じ filetype=vue に
-- 反応するが、ここで排他的に振り分けることで片方だけが attach する。
function M.make_root_dir(predicate)
  return function(bufnr, on_dir)
    if not predicate(M.vue_major(bufnr)) then
      return
    end
    on_dir(vim.fs.root(bufnr, M.root_markers))
  end
end

-- on_init: vue_ls からの tsserver/request を typescript-tools/vtsls/ts_ls へ転送
function M.on_init(client)
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
end

M.init_options = {
  vue = {
    -- Hybrid Mode: typescript-tools が TypeScript を処理、vue_ls はテンプレート/CSS のみ
    hybridMode = true,
  },
  typescript = {
    -- プロジェクトの TypeScript を優先、なければグローバルを使用
    tsdk = '',
  },
}

M.settings = {
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
}

return M
