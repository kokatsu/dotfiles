---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action
local platform = require('platform')

-- ダブルプレス確認用のグローバル状態
wezterm.GLOBAL = wezterm.GLOBAL or {}

-- プラットフォームユーティリティをローカル変数にバインド
local is_wsl_domain = platform.is_wsl_domain

--- ダブルプレスで実行するアクションを作成
--- 1回目はステータスバーにメッセージを表示し、タイムアウト内に再度押すと実行
---@param key_name string キー名（状態管理用）
---@param action table 実行するアクション
---@param timeout_sec number タイムアウト（秒）
---@param message string? 1回目に表示するメッセージ（省略時は通知なし）
local function double_press_action(key_name, action, timeout_sec, message)
  return wezterm.action_callback(function(window, pane)
    local now = os.time()
    local last_press = wezterm.GLOBAL[key_name] or 0
    local elapsed = now - last_press

    if elapsed < timeout_sec then
      -- 2回目: アクションを実行し、ステータスをクリア
      wezterm.GLOBAL[key_name] = 0
      wezterm.GLOBAL.status_message = nil
      wezterm.GLOBAL.status_expire = nil
      window:set_right_status(wezterm.format({}))
      window:perform_action(action, pane)
    else
      -- 1回目: ステータスバーにメッセージを表示
      wezterm.GLOBAL[key_name] = now
      if message then
        local colors = require('colors')
        wezterm.GLOBAL.status_message = message
        wezterm.GLOBAL.status_expire = now + timeout_sec
        window:set_right_status(wezterm.format({
          { Background = { Color = colors.palette.red } },
          { Foreground = { Color = colors.palette.crust } },
          { Text = ' ' .. message .. ' ' },
        }))
      end
    end
  end)
end

--- 修飾子を変換する
---@param mods string 修飾子文字列
---@param mods_map table 修飾子マッピング { PRIMARY = 'CMD', SECONDARY = 'CTRL' }
---@return string 変換後の修飾子
local function convert_mods(mods, mods_map)
  local result = mods
  for placeholder, actual in pairs(mods_map) do
    result = result:gsub(placeholder, actual)
  end
  return result
end

--- キーバインドの修飾子を変換する
---@param keys table[] キーバインドテーブル
---@param mods_map table 修飾子マッピング
---@return table[] 変換後のキーバインドテーブル
local function convert_keys(keys, mods_map)
  local result = {}
  for _, key in ipairs(keys) do
    local converted = {}
    for k, v in pairs(key) do
      if k == 'mods' then
        converted[k] = convert_mods(v, mods_map)
      else
        converted[k] = v
      end
    end
    table.insert(result, converted)
  end
  return result
end

--- キーテーブルをマージする
---@param ... table[] マージするキーテーブル
---@return table マージされたキーテーブル
local function merge_keys(...)
  local result = {}
  for _, keys in ipairs({ ... }) do
    for _, key in ipairs(keys) do
      table.insert(result, key)
    end
  end
  return result
end

-- 共通キーバインド（プラットフォーム非依存）
-- ペイン/タブ/レイアウト管理は herdr に全面委譲したため、
-- WezTerm は GUI シェル (コピペ・フォント・QuickSelect 等) に徹する。
local common_keys = {
  -- `Shift + Enter` で 改行を送信
  -- https://zenn.dev/glaucus03/articles/070589323cb450
  { key = 'Enter', mods = 'SHIFT', action = act.SendString('\n') },
  -- `Alt + k` で Slack の未読バッジをクリアする。
  -- 常駐リスナー (windows/slack-watch) がこのマーカーを見つけて通知センターから
  -- Slack のトーストを消すので、Windows の通知センター側も同時に空になる
  {
    key = 'k',
    mods = 'ALT',
    action = wezterm.action_callback(function(_window, _pane)
      local userprofile = os.getenv('USERPROFILE')
      if not userprofile then
        return
      end

      local dir = userprofile .. '\\.cache\\slack-watch\\'
      local tmp = dir .. 'clear.request.tmp'
      local file = io.open(tmp, 'w')
      if not file then
        return
      end

      file:close()
      -- 常駐はファイル監視で即座に反応する。書き込み途中を消されないよう rename で置く
      os.rename(tmp, dir .. 'clear.request')
    end),
  },
  -- `Ctrl + q` で WezTerm を終了（2度押しで確認）
  -- herdr セッションはサーバ側に残るため、次回起動時にそのまま復帰する
  {
    key = 'q',
    mods = 'CTRL',
    action = double_press_action(
      'ctrl_q_press',
      act.QuitApplication,
      2, -- 2秒以内に再度押すと実行
      'もう一度 Ctrl+Q で終了'
    ),
  },
}

-- 統一キーバインド (PRIMARY/SECONDARY をプラットフォームごとに変換)
-- Windows: PRIMARY=CTRL, SECONDARY=ALT
-- macOS: PRIMARY=CTRL, SECONDARY=ALT (Karabiner でターミナルアプリ以外でのみ Ctrl↔Cmd 入替)
-- これにより、WSL と macOS で同じ操作感を実現
local unified_keys = {
  -- `PRIMARY + c` でクリップボードにコピー
  { key = 'c', mods = 'PRIMARY', action = act.CopyTo('Clipboard') },
  -- `PRIMARY + Shift + c` でキャンセル (SIGINT)
  { key = 'C', mods = 'PRIMARY', action = act.SendKey({ key = 'c', mods = 'CTRL' }) },
  -- `PRIMARY + v` でクリップボードからペースト
  { key = 'v', mods = 'PRIMARY', action = act.PasteFrom('Clipboard') },
  -- `PRIMARY + Shift + n` で新しいウィンドウを作成 (herdr 外の生シェル escape hatch)
  { key = 'N', mods = 'PRIMARY', action = act.SpawnWindow },
  -- `PRIMARY + 左矢印` で前の単語に移動 (Esc+b)
  -- selene: allow(bad_string_escape)
  { key = 'LeftArrow', mods = 'PRIMARY', action = act.SendString('\x1bb') },
  -- `PRIMARY + 右矢印` で次の単語に移動 (Esc+f)
  -- selene: allow(bad_string_escape)
  { key = 'RightArrow', mods = 'PRIMARY', action = act.SendString('\x1bf') },
  -- `PRIMARY + Shift + L` でデバッグオーバーレイを表示
  { key = 'L', mods = 'PRIMARY', action = act.ShowDebugOverlay },
  -- `PRIMARY + ;` でフォントを大きくする
  { key = ';', mods = 'PRIMARY', action = act.IncreaseFontSize },
  -- `PRIMARY + -` でフォントを小さくする
  { key = '-', mods = 'PRIMARY', action = act.DecreaseFontSize },
  -- `PRIMARY + :` でフォントをリセット
  { key = ':', mods = 'PRIMARY', action = act.ResetFontSize },
  -- `PRIMARY + Backspace` で単語を削除
  { key = 'Backspace', mods = 'PRIMARY', action = act.SendKey({ key = 'w', mods = 'CTRL' }) },
  -- `PRIMARY + Shift + X` でコピーモードをアクティブにする
  { key = 'X', mods = 'PRIMARY', action = act.ActivateCopyMode },
  -- QuickSelect モード
  { key = 'q', mods = 'SECONDARY', action = act.QuickSelect },
  -- コマンドパレット
  { key = 'p', mods = 'PRIMARY|SHIFT', action = act.ActivateCommandPalette },
}

-- Windows 固有キーバインド
local windows_specific_keys = {
  -- `Ctrl + Space` (herdr prefix) で日本語 IME をオフにしてから prefix を送る。
  -- herdr の switch_ascii_input_source_in_prefix は WSL 内の Linux プロセスからは
  -- Windows の IME に届かないため、Windows 側で動く WezTerm が代行する。
  -- Windows 側の zenhan.exe は起動できないため、Neovim の InsertLeave と同じく
  -- WSL 内の zenhan を wsl.exe 経由で起こす。
  -- 起動失敗で callback が中断すると prefix 自体が届かなくなるので pcall で保護する。
  -- 非同期起動 (実測 0.3〜0.4 秒) のため、IME が ON の状態で prefix 直後 0.3 秒以内に
  -- 打った次のキーは食われうる。同期待ちは prefix 転送自体を遅らせるので採らない。
  -- prefix 終了を WezTerm は検知できないため IME はオフのまま残る
  {
    key = 'Space',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      -- PowerShell など WSL 以外のペインでは IME を触らない
      if is_wsl_domain(pane) then
        local ok, err = pcall(wezterm.background_child_process, { 'wsl.exe', '-e', 'zenhan', '0' })
        if not ok then
          wezterm.log_error('zenhan: ' .. tostring(err))
        end
      end
      window:perform_action(act.SendKey({ key = 'Space', mods = 'CTRL' }), pane)
    end),
  },
  -- `Alt + y` で新しいタブで PowerShell を起動
  {
    key = 'y',
    mods = 'ALT',
    action = act.SpawnCommandInNewTab({ args = { 'powershell.exe' }, domain = { DomainName = 'local' } }),
  },
  -- `Alt + s` で新しいタブで WSL に SSH 接続 (yazi 画像プレビュー用)
  {
    key = 's',
    mods = 'ALT',
    action = act.SpawnCommandInNewTab({ args = { 'ssh', '127.0.0.1' }, domain = { DomainName = 'local' } }),
  },
  -- `Alt + p` で最新のスクリーンショットのWSLパスを入力（WSLドメインのみ）
  -- 外部プロセス不要: wezterm.glob() でファイル一覧を取得
  {
    key = 'p',
    mods = 'ALT',
    action = wezterm.action_callback(function(window, pane)
      if not is_wsl_domain(pane) then
        return
      end

      local screenshot_dir = os.getenv('SCREENSHOT_DIR')
      if not screenshot_dir then
        window:toast_notification('WezTerm', 'SCREENSHOT_DIR が設定されていません', nil, 3000)
        return
      end
      local files = wezterm.glob(screenshot_dir .. '\\*.png')

      if #files == 0 then
        window:toast_notification('WezTerm', 'スクリーンショットが見つかりません', nil, 3000)
        return
      end

      -- ファイル名にタイムスタンプが含まれるのでソートして最新を取得
      table.sort(files)
      local latest = files[#files]

      -- Windows パスを WSL パスに変換: C:\... -> /mnt/c/...
      local wsl_path = latest:gsub('\\', '/')
      wsl_path = wsl_path:gsub('^(%a):/', function(drive)
        return '/mnt/' .. drive:lower() .. '/'
      end)

      pane:send_text('"' .. wsl_path .. '"')
    end),
  },
}

-- macOS 固有キーバインド
-- Karabiner でターミナルアプリ以外でのみ Ctrl↔Cmd 入替のため、物理 Ctrl = Ctrl として届く
-- 注意: OPT+矢印 を SendString で潰すと herdr の focus_pane (alt+矢印) に
-- キーが届かなくなるため、単語移動は Ctrl+矢印 に一本化している
local darwin_specific_keys = {}

-- コピーモードのキーテーブル（Vim風操作）
local copy_mode = {
  -- 移動
  { key = 'h', mods = 'NONE', action = act.CopyMode('MoveLeft') },
  { key = 'j', mods = 'NONE', action = act.CopyMode('MoveDown') },
  { key = 'k', mods = 'NONE', action = act.CopyMode('MoveUp') },
  { key = 'l', mods = 'NONE', action = act.CopyMode('MoveRight') },
  -- 行頭・行末に移動
  { key = '^', mods = 'NONE', action = act.CopyMode('MoveToStartOfLineContent') },
  { key = '$', mods = 'NONE', action = act.CopyMode('MoveToEndOfLineContent') },
  { key = '0', mods = 'NONE', action = act.CopyMode('MoveToStartOfLine') },
  -- 選択範囲の端に移動
  { key = 'o', mods = 'NONE', action = act.CopyMode('MoveToSelectionOtherEnd') },
  { key = 'O', mods = 'NONE', action = act.CopyMode('MoveToSelectionOtherEndHoriz') },
  -- ジャンプを繰り返す
  ---@diagnostic disable-next-line: param-type-mismatch
  { key = ';', mods = 'NONE', action = act.CopyMode('JumpAgain') },
  -- 単語ごと移動
  { key = 'w', mods = 'NONE', action = act.CopyMode('MoveForwardWord') },
  { key = 'b', mods = 'NONE', action = act.CopyMode('MoveBackwardWord') },
  { key = 'e', mods = 'NONE', action = act.CopyMode('MoveForwardWordEnd') },
  -- ジャンプ機能 t f
  { key = 't', mods = 'NONE', action = act.CopyMode({ JumpForward = { prev_char = true } }) },
  { key = 'f', mods = 'NONE', action = act.CopyMode({ JumpForward = { prev_char = false } }) },
  { key = 'T', mods = 'NONE', action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
  { key = 'F', mods = 'NONE', action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
  -- 一番下・一番上へ
  { key = 'G', mods = 'NONE', action = act.CopyMode('MoveToScrollbackBottom') },
  { key = 'g', mods = 'NONE', action = act.CopyMode('MoveToScrollbackTop') },
  -- Viewport内移動
  { key = 'H', mods = 'NONE', action = act.CopyMode('MoveToViewportTop') },
  { key = 'L', mods = 'NONE', action = act.CopyMode('MoveToViewportBottom') },
  { key = 'M', mods = 'NONE', action = act.CopyMode('MoveToViewportMiddle') },
  -- スクロール
  { key = 'b', mods = 'CTRL', action = act.CopyMode('PageUp') },
  { key = 'f', mods = 'CTRL', action = act.CopyMode('PageDown') },
  { key = 'd', mods = 'CTRL', action = act.CopyMode({ MoveByPage = 0.5 }) },
  { key = 'u', mods = 'CTRL', action = act.CopyMode({ MoveByPage = -0.5 }) },
  -- 範囲選択モード
  { key = 'v', mods = 'NONE', action = act.CopyMode({ SetSelectionMode = 'Cell' }) },
  { key = 'v', mods = 'CTRL', action = act.CopyMode({ SetSelectionMode = 'Block' }) },
  { key = 'V', mods = 'NONE', action = act.CopyMode({ SetSelectionMode = 'Line' }) },
  -- コピー
  { key = 'y', mods = 'NONE', action = act.CopyTo('Clipboard') },
  -- 検索
  { key = '/', mods = 'NONE', action = act.Search({ CaseSensitiveString = '' }) },
  { key = '?', mods = 'NONE', action = act.Search({ CaseSensitiveString = '' }) },
  { key = 'n', mods = 'NONE', action = act.CopyMode('NextMatch') },
  { key = 'N', mods = 'NONE', action = act.CopyMode('PriorMatch') },
  -- コピーモードを終了
  {
    key = 'Enter',
    mods = 'NONE',
    ---@diagnostic disable-next-line: missing-fields
    action = act.Multiple({ { CopyTo = 'ClipboardAndPrimarySelection' }, { CopyMode = 'Close' } }),
  },
  { key = 'Escape', mods = 'NONE', action = act.CopyMode('Close') },
  { key = 'c', mods = 'CTRL', action = act.CopyMode('Close') },
  { key = 'q', mods = 'NONE', action = act.CopyMode('Close') },
}

-- 検索モードのキーテーブル
local search_mode = {
  { key = 'Enter', mods = 'NONE', action = act.CopyMode('PriorMatch') },
  { key = 'Escape', mods = 'NONE', action = act.CopyMode('Close') },
  { key = 'n', mods = 'CTRL', action = act.CopyMode('NextMatch') },
  { key = 'p', mods = 'CTRL', action = act.CopyMode('PriorMatch') },
  { key = 'r', mods = 'CTRL', action = act.CopyMode('CycleMatchType') },
  { key = 'u', mods = 'CTRL', action = act.CopyMode('ClearPattern') },
}

return {
  windows_keys = merge_keys(
    common_keys,
    convert_keys(unified_keys, { PRIMARY = 'CTRL', SECONDARY = 'ALT' }),
    windows_specific_keys
  ),
  darwin_keys = merge_keys(
    common_keys,
    convert_keys(unified_keys, { PRIMARY = 'CTRL', SECONDARY = 'ALT' }),
    darwin_specific_keys -- macOS固有キーを最後に配置して優先
  ),
  key_tables = {
    copy_mode = copy_mode,
    search_mode = search_mode,
  },
}
