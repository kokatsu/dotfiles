-- Autocmd設定

-- プラグインロードをログに記録し、未使用プラグインを通知
-- ログ: ~/.local/share/nvim/lazy-load.log
do
  local logfile = vim.fn.stdpath('data') .. '/lazy-load.log'
  local seconds_per_day = 86400
  local unused_days_threshold = 30
  local log_retention_days = 90

  -- lazy-load イベントをログに記録
  vim.api.nvim_create_autocmd('User', {
    pattern = 'LazyLoad',
    callback = function(event)
      local f = io.open(logfile, 'a')
      if f then
        f:write(os.date('%Y-%m-%d') .. '\t' .. event.data .. '\n')
        f:close()
      end
    end,
  })

  -- 起動時に未使用プラグインを検出して通知
  vim.api.nvim_create_autocmd('User', {
    pattern = 'VeryLazy',
    once = true,
    callback = function()
      local retention_threshold = os.date('%Y-%m-%d', os.time() - log_retention_days * seconds_per_day)
      local last_loaded = {}
      local retained = {}
      local total_lines = 0

      local f = io.open(logfile, 'r')
      if not f then
        return
      end

      -- ログからプラグインごとの最終ロード日を集計 + ローテーション対象を抽出
      for line in f:lines() do
        local date, name = line:match('^(%d%d%d%d%-%d%d%-%d%d)\t(.+)$')
        if date and name then
          total_lines = total_lines + 1
          if not last_loaded[name] or date > last_loaded[name] then
            last_loaded[name] = date
          end
          if date >= retention_threshold then
            retained[#retained + 1] = line
          end
        end
      end
      f:close()

      -- ログが空ならまだ収集期間中
      if not next(last_loaded) then
        return
      end

      -- ログの最古エントリが閾値未満なら猶予期間として通知をスキップ
      local oldest_date
      for _, date in pairs(last_loaded) do
        if not oldest_date or date < oldest_date then
          oldest_date = date
        end
      end
      local threshold_date = os.date('%Y-%m-%d', os.time() - unused_days_threshold * seconds_per_day)
      if oldest_date and oldest_date > threshold_date then
        -- ログ収集開始から unused_days_threshold 日未満なので通知しない
        return
      end

      -- ログローテーション: 直近N日分のみ保持（一時ファイル→renameでアトミックに置換）
      -- 削除対象がなければ書き換えをスキップ
      if #retained ~= total_lines then
        local ok, err = pcall(function()
          local tmpfile = logfile .. '.tmp'
          local fw = io.open(tmpfile, 'w')
          if not fw then
            error('Cannot open tmp file: ' .. tmpfile)
          end
          for _, line in ipairs(retained) do
            fw:write(line .. '\n')
          end
          fw:close()
          os.rename(tmpfile, logfile)
        end)
        if not ok then
          vim.notify('Log rotation failed: ' .. tostring(err), vim.log.levels.WARN)
        end
      end

      -- lazy.nvim の全プラグインと突き合わせ
      local plugins = require('lazy').plugins()
      local unused = {}
      for _, plugin in ipairs(plugins) do
        local name = plugin.name
        -- lazy.nvim 本体・依存ライブラリ・startプラグインは除外
        -- startプラグイン(lazy=false)はLazyLoadイベントを発火しないためログに残らない
        -- NOTE: plugin._.dep は lazy.nvim の内部API
        -- v11以降で plugin._.kind 等に変更される可能性あり。アップデート時に要確認
        if name ~= 'lazy.nvim' and not (plugin._ and plugin._.dep) and plugin.lazy then
          local last = last_loaded[name]
          if not last then
            -- 新規追加プラグインには猶予期間を設ける
            -- plugin._.installed はインストール時のタイムスタンプ（秒）
            local installed_at = plugin._ and plugin._.installed
            if not installed_at or (os.time() - installed_at) >= unused_days_threshold * seconds_per_day then
              table.insert(unused, name .. ' (ログに記録なし)')
            end
          elseif last < threshold_date then
            table.insert(unused, name .. ' (最終: ' .. last .. ')')
          end
        end
      end

      if #unused > 0 then
        table.sort(unused)
        vim.notify(
          unused_days_threshold
            .. '日以上ロードされていないプラグイン:\n'
            .. table.concat(unused, '\n'),
          vim.log.levels.WARN,
          { title = 'Unused Plugins' }
        )
      end
    end,
  })
end

-- ヤンク時にハイライト表示
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank({ timeout = 200 })
  end,
})

-- ファイル再オープン時に前回のカーソル位置へ移動
vim.api.nvim_create_autocmd('BufReadPost', {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(0) then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

-- snacks_dashboardでの:qをフリーズさせない
-- GIFアニメーション(chafa)が実行中のため、:qaで強制終了する
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'snacks_dashboard',
  callback = function()
    vim.keymap.set('ca', 'q', function()
      if vim.fn.getcmdtype() == ':' and vim.fn.getcmdline() == 'q' then
        return 'qa'
      end
      return 'q'
    end, { buffer = true, expr = true })
    vim.keymap.set('ca', 'q!', function()
      if vim.fn.getcmdtype() == ':' and vim.fn.getcmdline() == 'q!' then
        return 'qa!'
      end
      return 'q!'
    end, { buffer = true, expr = true })
  end,
})

-- https://minerva.mamansoft.net/Notes/%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB%E3%81%8C%E5%A4%89%E6%9B%B4%E3%81%95%E3%82%8C%E3%81%9F%E3%82%89%E8%87%AA%E5%8B%95%E3%81%A7%E5%86%8D%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF+(Neovim)
-- 外部からファイルを変更されたら反映する
-- CursorHold/CursorHoldIを追加してClaude Code等の外部ツールによる変更を検知
vim.api.nvim_create_autocmd({ 'WinEnter', 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  pattern = '*',
  command = 'checktime',
})

-- 外部でファイルが変更された後、LSPに変更を通知して診断を更新
-- Claude Code等の外部ツールによる変更後にrust-analyzer等の診断を反映させる
vim.api.nvim_create_autocmd('FileChangedShellPost', {
  pattern = '*',
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
      local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
      }
      local sync = client.server_capabilities.textDocumentSync
      local save_opts = type(sync) == 'table' and sync.save or nil
      if type(save_opts) == 'table' and save_opts.includeText then
        params.text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') .. '\n'
      end
      client:notify('textDocument/didSave', params)
    end
  end,
})

local os_utils = require('utils.os')

-- WSLの場合はInsertモードから離れる時にzenhanを実行
local os_name = os_utils.detect_os()
local group = vim.api.nvim_create_augroup('kyoh86-conf-ime', {})
if os_name == 'wsl' then
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    command = 'silent! !zenhan 0',
  })
end

-- フォーカスを失ったときにVisualモードを解除する
-- 別ペーンから戻ったときにVisualモードに気づかず操作するミスを防ぐ
vim.api.nvim_create_autocmd('FocusLost', {
  callback = function()
    local mode = vim.api.nvim_get_mode().mode
    if mode == 'v' or mode == 'V' or mode == '\22' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end
  end,
})

-- Claude Code用プロンプト編集設定
-- .claude ファイルで @ を押すと mini.pick でファイル補完を発動
-- Claude Code では @ファイルパス でファイルを参照できる
-- https://zenn.dev/shisashi/articles/0ba22e272d6f2f
vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = '*.claude',
  callback = function()
    vim.keymap.set('i', '@', function()
      local pick = require('mini.pick')

      -- カーソル後の単語を初期クエリにする
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local after_cursor = line:sub(col + 1)
      local initial_query = after_cursor:match('^(%S+)') or ''

      -- mini.pick でファイル選択
      local selected_path = pick.builtin.files({}, {
        source = {
          name = 'Files (@reference)',
          choose = function() end, -- ファイルを開かず、パスの返却のみ行う
        },
        window = { prompt_prefix = '@' },
        query = initial_query,
      })

      -- 選択結果の処理
      if selected_path then
        -- 初期クエリとして使った文字列を削除
        if initial_query ~= '' then
          local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
          local cur_line = vim.api.nvim_get_current_line()
          local new_line = cur_line:sub(1, cur_col) .. cur_line:sub(cur_col + 1 + #initial_query)
          vim.api.nvim_set_current_line(new_line)
        end
        vim.api.nvim_put({ '@' .. selected_path .. ' ' }, '', false, true)
      else
        -- キャンセル時は @ のみ
        vim.api.nvim_put({ '@' }, '', false, true)
      end

      -- インサートモードに戻る
      vim.schedule(function()
        vim.cmd('startinsert!')
      end)
    end, { buffer = true, noremap = true, desc = 'Claude Code: Insert @filepath reference' })
  end,
})
