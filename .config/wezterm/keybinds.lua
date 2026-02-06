---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action
local platform = require('platform')

wezterm.on('maximize-window', function(window, _)
  window:maximize()
end)

-- ダブルプレス確認用のグローバル状態
wezterm.GLOBAL = wezterm.GLOBAL or {}

-- プラットフォームユーティリティをローカル変数にバインド
local is_wsl_domain = platform.is_wsl_domain

--- ダブルプレスで実行するアクションを作成
---@param key_name string キー名（状態管理用）
---@param action table 実行するアクション
---@param timeout_sec number タイムアウト（秒）
---@param message string 1回目に表示するメッセージ
local function double_press_action(key_name, action, timeout_sec, message)
  return wezterm.action_callback(function(window, pane)
    local now = os.time()
    local last_press = wezterm.GLOBAL[key_name] or 0
    local elapsed = now - last_press

    if elapsed < timeout_sec then
      -- 2回目: アクションを実行
      wezterm.GLOBAL[key_name] = 0
      window:perform_action(action, pane)
    else
      -- 1回目: 通知を表示して待機
      wezterm.GLOBAL[key_name] = now
      window:toast_notification('WezTerm', message, nil, timeout_sec * 1000)
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
local common_keys = {
  -- `Alt + o` で前回の出力をクリップボードにコピー
  {
    key = 'o',
    mods = 'ALT',
    action = wezterm.action_callback(function(window, pane)
      local zones = pane:get_semantic_zones('Output')
      if #zones > 0 then
        local txt = pane:get_text_from_semantic_zone(zones[#zones])
        window:copy_to_clipboard(txt)
      end
    end),
  },
  -- `Alt + e` でプロンプトエディタを開く（tmux display-popup使用）
  -- tmux内: tmuxがAlt+eを捕捉してdisplay-popupを開く
  -- tmux外: シェルにキーが送られるだけ（何も起きない）
  {
    key = 'e',
    mods = 'ALT',
    action = act.SendKey({ key = 'e', mods = 'ALT' }),
  },
  -- `Shift + Enter` で 改行を送信
  -- https://zenn.dev/glaucus03/articles/070589323cb450
  { key = 'Enter', mods = 'SHIFT', action = act.SendString('\n') },
  -- `Alt + ;` で右分割レイアウト (左 | 右上/右下)
  {
    key = ';',
    mods = 'ALT',
    action = wezterm.action_callback(function(_, pane)
      local cwd_uri = pane:get_current_working_dir()
      local cwd = cwd_uri and cwd_uri.file_path or nil
      local right = pane:split({ direction = 'Right', size = 0.5, cwd = cwd })
      right:split({ direction = 'Bottom', size = 0.5, cwd = cwd })
    end),
  },
  -- `Alt + \` でレイアウト選択
  {
    key = '\\',
    mods = 'ALT',
    action = act.InputSelector({
      title = 'Select Layout',
      choices = {
        { label = '左 | 右上/右下', id = 'right-split' },
        { label = '上 / 下左|下右', id = 'bottom-split' },
        { label = '3列均等', id = 'three-cols' },
      },
      action = wezterm.action_callback(function(_, pane, id, _)
        local cwd_uri = pane:get_current_working_dir()
        local cwd = cwd_uri and cwd_uri.file_path or nil
        if id == 'right-split' then
          local right = pane:split({ direction = 'Right', size = 0.5, cwd = cwd })
          right:split({ direction = 'Bottom', size = 0.5, cwd = cwd })
        elseif id == 'bottom-split' then
          local bottom = pane:split({ direction = 'Bottom', size = 0.5, cwd = cwd })
          bottom:split({ direction = 'Right', size = 0.5, cwd = cwd })
        elseif id == 'three-cols' then
          local right = pane:split({ direction = 'Right', size = 0.66, cwd = cwd })
          right:split({ direction = 'Right', size = 0.5, cwd = cwd })
        end
      end),
    }),
  },
  -- `Ctrl + q` で終了（2度押しで確認）
  {
    key = 'q',
    mods = 'CTRL',
    action = double_press_action(
      'ctrl_q_press',
      act.SendKey({ key = 'q', mods = 'CTRL' }),
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
  -- `PRIMARY + s` で水平分割
  { key = 's', mods = 'PRIMARY', action = act.SplitHorizontal({}) },
  -- `PRIMARY + Shift + s` で垂直分割
  { key = 'S', mods = 'PRIMARY', action = act.SplitVertical({}) },
  -- `PRIMARY + t` で新しいタブを作成
  { key = 't', mods = 'PRIMARY', action = act.SpawnCommandInNewTab({ cwd = wezterm.home_dir }) },
  -- `PRIMARY + Shift + t` で現在のタブを新しいタブにコピー
  { key = 'T', mods = 'PRIMARY', action = act.SpawnTab('CurrentPaneDomain') },
  -- `PRIMARY + n` で新しいウィンドウを作成
  { key = 'n', mods = 'PRIMARY', action = act.SpawnCommandInNewWindow({ cwd = wezterm.home_dir }) },
  -- `PRIMARY + Shift + n` で現在のウィンドウを新しいウィンドウにコピー
  { key = 'N', mods = 'PRIMARY', action = act.SpawnWindow },
  -- `PRIMARY + Tab` で右のタブに移動
  { key = 'Tab', mods = 'PRIMARY', action = act.ActivateTabRelative(1) },
  -- `PRIMARY + Shift + Tab` で左のタブに移動
  { key = 'Tab', mods = 'PRIMARY|SHIFT', action = act.ActivateTabRelative(-1) },
  -- `PRIMARY + z` でペインをズーム（トグル）
  { key = 'z', mods = 'PRIMARY', action = act.TogglePaneZoomState },
  -- `SECONDARY + w` で現在のペインを閉じる
  { key = 'w', mods = 'SECONDARY', action = act.CloseCurrentPane({ confirm = false }) },
  -- `SECONDARY + 矢印` でペイン移動
  { key = 'LeftArrow', mods = 'SECONDARY', action = act.ActivatePaneDirection('Left') },
  { key = 'RightArrow', mods = 'SECONDARY', action = act.ActivatePaneDirection('Right') },
  { key = 'UpArrow', mods = 'SECONDARY', action = act.ActivatePaneDirection('Up') },
  { key = 'DownArrow', mods = 'SECONDARY', action = act.ActivatePaneDirection('Down') },
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
  -- `PRIMARY + [` でタブを左に移動
  { key = '[', mods = 'PRIMARY', action = act.MoveTabRelative(-1) },
  -- `PRIMARY + ]` でタブを右に移動
  { key = ']', mods = 'PRIMARY', action = act.MoveTabRelative(1) },
  -- `PRIMARY + Backspace` で単語を削除
  { key = 'Backspace', mods = 'PRIMARY', action = act.SendKey({ key = 'w', mods = 'CTRL' }) },
  -- `PRIMARY + 1-9` でタブ切替
  { key = '1', mods = 'PRIMARY', action = act.ActivateTab(0) },
  { key = '2', mods = 'PRIMARY', action = act.ActivateTab(1) },
  { key = '3', mods = 'PRIMARY', action = act.ActivateTab(2) },
  { key = '4', mods = 'PRIMARY', action = act.ActivateTab(3) },
  { key = '5', mods = 'PRIMARY', action = act.ActivateTab(4) },
  { key = '6', mods = 'PRIMARY', action = act.ActivateTab(5) },
  { key = '7', mods = 'PRIMARY', action = act.ActivateTab(6) },
  { key = '8', mods = 'PRIMARY', action = act.ActivateTab(7) },
  { key = '9', mods = 'PRIMARY', action = act.ActivateLastTab },
  -- `PRIMARY + Shift + 矢印` でペインリサイズ
  { key = 'LeftArrow', mods = 'PRIMARY|SHIFT', action = act.AdjustPaneSize({ 'Left', 1 }) },
  { key = 'RightArrow', mods = 'PRIMARY|SHIFT', action = act.AdjustPaneSize({ 'Right', 1 }) },
  { key = 'UpArrow', mods = 'PRIMARY|SHIFT', action = act.AdjustPaneSize({ 'Up', 1 }) },
  { key = 'DownArrow', mods = 'PRIMARY|SHIFT', action = act.AdjustPaneSize({ 'Down', 1 }) },
  -- `SECONDARY + Shift + l` でペインを左に回転
  { key = 'L', mods = 'SECONDARY|SHIFT', action = act.RotatePanes('CounterClockwise') },
  -- `SECONDARY + Shift + r` でペインを右に回転
  { key = 'R', mods = 'SECONDARY|SHIFT', action = act.RotatePanes('Clockwise') },
  -- `PRIMARY + Shift + X` でコピーモードをアクティブにする
  { key = 'X', mods = 'PRIMARY', action = act.ActivateCopyMode },
  -- `SECONDARY + f` で画面を最大化
  { key = 'f', mods = 'SECONDARY', action = act.EmitEvent('maximize-window') },
  -- QuickSelect モード
  { key = 'q', mods = 'SECONDARY', action = act.QuickSelect },
  -- コマンドパレット
  { key = 'p', mods = 'PRIMARY|SHIFT', action = act.ActivateCommandPalette },
}

-- Windows 固有キーバインド
local windows_specific_keys = {
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
local darwin_specific_keys = {
  -- Option + 矢印で単語移動（macOS標準の動作）
  -- selene: allow(bad_string_escape)
  { key = 'LeftArrow', mods = 'OPT', action = act.SendString('\x1bb') },
  -- selene: allow(bad_string_escape)
  { key = 'RightArrow', mods = 'OPT', action = act.SendString('\x1bf') },
}

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

--- 統一キーバインドを取得する
---@param mods_map table 修飾子マッピング { PRIMARY = 'CTRL', SECONDARY = 'ALT' }
---@return table[] 変換後のキーバインドテーブル
local function get_unified_keys(mods_map)
  return convert_keys(unified_keys, mods_map)
end

return {
  -- 新しいAPI: 修飾子マッピングを渡して統一キーを取得
  get_unified_keys = get_unified_keys,
  common_keys = common_keys,
  windows_specific_keys = windows_specific_keys,
  darwin_specific_keys = darwin_specific_keys,
  merge_keys = merge_keys,
  -- 後方互換性のため残す
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
