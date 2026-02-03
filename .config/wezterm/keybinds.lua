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
local non_wsl_action = platform.non_wsl_action

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
  -- `Shift + Enter` で 改行を送信
  -- https://zenn.dev/glaucus03/articles/070589323cb450
  { key = 'Enter', mods = 'SHIFT', action = act.SendString('\n') },
  -- NOTE: `Alt + ;`, `Alt + \` のレイアウト機能は zellij に移行
  -- zellij の config.kdl で設定: Alt+; (右分割), Alt+' (下分割), Alt+3 (3列), Alt+\ (選択)
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
  -- `PRIMARY + Shift + X` でコピーモードをアクティブにする
  { key = 'X', mods = 'PRIMARY', action = act.ActivateCopyMode },
  -- `SECONDARY + f` で画面を最大化
  { key = 'f', mods = 'SECONDARY', action = act.EmitEvent('maximize-window') },
  -- QuickSelect モード
  { key = 'q', mods = 'SECONDARY', action = act.QuickSelect },
  -- コマンドパレット
  { key = 'p', mods = 'PRIMARY|SHIFT', action = act.ActivateCommandPalette },
}

-- ペイン操作キーバインド (WSL以外でのみ有効、WSLではtmuxを使用)
-- Windows: Ctrl+s/Ctrl+Shift+s/Ctrl+z/Alt+w 等をtmuxに転送
local pane_keys = {
  -- `PRIMARY + s` で水平分割 (WSLではCtrl+sをtmuxに転送)
  { key = 's', mods = 'PRIMARY', action = non_wsl_action(act.SplitHorizontal({}), { key = 's', mods = 'CTRL' }) },
  -- `PRIMARY + z` でペインをズーム（トグル）(WSLではCtrl+zをtmuxに転送)
  { key = 'z', mods = 'PRIMARY', action = non_wsl_action(act.TogglePaneZoomState, { key = 'z', mods = 'CTRL' }) },
  -- `SECONDARY + w` でペインを閉じる (WSLではAlt+wをtmuxに転送)
  -- Note: SendKeyではAlt+wが正しく送信されないため、ESCシーケンスを直接送信
  {
    key = 'w',
    mods = 'SECONDARY',
    action = non_wsl_action(act.CloseCurrentPane({ confirm = false }), act.SendString('\x1bw')),
  },
  -- `SECONDARY + Shift + 矢印` でペイン移動 (WSLではAlt+矢印をtmuxに転送)
  {
    key = 'LeftArrow',
    mods = 'SECONDARY|SHIFT',
    action = non_wsl_action(act.ActivatePaneDirection('Left'), { key = 'LeftArrow', mods = 'ALT' }),
  },
  {
    key = 'RightArrow',
    mods = 'SECONDARY|SHIFT',
    action = non_wsl_action(act.ActivatePaneDirection('Right'), { key = 'RightArrow', mods = 'ALT' }),
  },
  {
    key = 'UpArrow',
    mods = 'SECONDARY|SHIFT',
    action = non_wsl_action(act.ActivatePaneDirection('Up'), { key = 'UpArrow', mods = 'ALT' }),
  },
  {
    key = 'DownArrow',
    mods = 'SECONDARY|SHIFT',
    action = non_wsl_action(act.ActivatePaneDirection('Down'), { key = 'DownArrow', mods = 'ALT' }),
  },
  -- `PRIMARY + Shift + 矢印` でペインリサイズ (WSLではtmuxのAlt+=/- を使用、無効化)
  { key = 'LeftArrow', mods = 'PRIMARY|SHIFT', action = non_wsl_action(act.AdjustPaneSize({ 'Left', 1 }), nil) },
  { key = 'RightArrow', mods = 'PRIMARY|SHIFT', action = non_wsl_action(act.AdjustPaneSize({ 'Right', 1 }), nil) },
  { key = 'UpArrow', mods = 'PRIMARY|SHIFT', action = non_wsl_action(act.AdjustPaneSize({ 'Up', 1 }), nil) },
  { key = 'DownArrow', mods = 'PRIMARY|SHIFT', action = non_wsl_action(act.AdjustPaneSize({ 'Down', 1 }), nil) },
  -- `SECONDARY + Shift + l` でペインを左に回転 (WSLではAlt+Shift+lをtmuxに転送)
  {
    key = 'L',
    mods = 'SECONDARY|SHIFT',
    action = non_wsl_action(act.RotatePanes('CounterClockwise'), { key = 'L', mods = 'ALT|SHIFT' }),
  },
  -- `SECONDARY + Shift + r` でペインを右に回転 (WSLではAlt+Shift+rをtmuxに転送)
  {
    key = 'R',
    mods = 'SECONDARY|SHIFT',
    action = non_wsl_action(act.RotatePanes('Clockwise'), { key = 'R', mods = 'ALT|SHIFT' }),
  },
}

-- Windows 固有キーバインド
local windows_specific_keys = {
  -- `Alt + y` で新しいタブで PowerShell を起動
  {
    key = 'y',
    mods = 'ALT',
    action = act.SpawnCommandInNewTab({ args = { 'powershell.exe' }, domain = { DomainName = 'local' } }),
  },
  -- `Ctrl+Shift+s` で上下分割 (WSLではtmux prefix+dを送信)
  {
    key = 'S',
    mods = 'CTRL',
    action = non_wsl_action(
      act.SplitVertical({}),
      act.Multiple({
        act.SendKey({ key = 'b', mods = 'CTRL' }),
        act.SendKey({ key = 'd' }),
      })
    ),
  },
  -- https://picton.uk/blog/claude-code-image-paste-wezterm/
  -- `Alt + p` でクリップボードの画像を保存してWSLパスを出力（WSLドメインのみ）
  {
    key = 'p',
    mods = 'ALT',
    action = wezterm.action_callback(function(window, pane)
      -- WSLドメインでない場合は何もしない
      if not is_wsl_domain(pane) then
        return
      end

      local timestamp = os.date('%Y%m%d_%H%M%S')
      local filename = 'screenshot_' .. timestamp .. '.png'
      local filepath = 'C:\\tmp\\' .. filename
      local wsl_path = '/mnt/c/tmp/' .. filename

      -- wezterm.run_child_process で PowerShell を実行（ウィンドウなし）
      local success, stdout, stderr = wezterm.run_child_process({
        'powershell.exe',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        string.format(
          [[Add-Type -AssemblyName System.Windows.Forms; if (-not (Test-Path 'C:\tmp')) { New-Item -ItemType Directory -Path 'C:\tmp' | Out-Null }; $img = [System.Windows.Forms.Clipboard]::GetImage(); if ($img) { $img.Save('%s'); Write-Output '%s' } else { Write-Output 'No image' }]],
          filepath,
          wsl_path
        ),
      })

      if success then
        local result = stdout:gsub('%s+$', '')
        if result ~= 'No image' and result ~= '' then
          pane:send_text(result)
        else
          window:toast_notification('WezTerm', 'クリップボードに画像がありません', nil, 3000)
        end
      else
        window:toast_notification('WezTerm', 'エラー: ' .. stderr, nil, 3000)
      end
    end),
  },
}

-- macOS 固有キーバインド
-- Karabiner でターミナルアプリ以外でのみ Ctrl↔Cmd 入替のため、物理 Ctrl = Ctrl として届く
-- macOSではtmuxを使用するため、ペイン操作はtmuxに委譲
local darwin_specific_keys = {
  -- Option + 矢印で単語移動（macOS標準の動作）
  -- selene: allow(bad_string_escape)
  { key = 'LeftArrow', mods = 'OPT', action = act.SendString('\x1bb') },
  -- selene: allow(bad_string_escape)
  { key = 'RightArrow', mods = 'OPT', action = act.SendString('\x1bf') },
  -- `Ctrl+Shift+s` で上下分割 (tmux prefix+d を送信)
  {
    key = 'S',
    mods = 'CTRL',
    action = act.Multiple({
      act.SendKey({ key = 'b', mods = 'CTRL' }),
      act.SendKey({ key = 'd' }),
    }),
  },
  -- `Alt+w` でtmuxペインを閉じる (pane_keysを上書き、WezTermペインではなくtmuxペインを閉じる)
  -- selene: allow(bad_string_escape)
  { key = 'w', mods = 'ALT', action = act.SendString('\x1bw') },
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

--- ペイン操作キーバインドを取得する（修飾子変換付き）
--- pane_keysはaction_callbackを使用しているため、modsのみ変換
---@param mods_map table 修飾子マッピング { PRIMARY = 'CTRL', SECONDARY = 'ALT' }
---@return table[] 変換後のキーバインドテーブル
local function get_pane_keys(mods_map)
  return convert_keys(pane_keys, mods_map)
end

return {
  -- 新しいAPI: 修飾子マッピングを渡して統一キーを取得
  get_unified_keys = get_unified_keys,
  get_pane_keys = get_pane_keys,
  common_keys = common_keys,
  windows_specific_keys = windows_specific_keys,
  darwin_specific_keys = darwin_specific_keys,
  merge_keys = merge_keys,
  -- 後方互換性のため残す
  windows_keys = merge_keys(
    common_keys,
    convert_keys(unified_keys, { PRIMARY = 'CTRL', SECONDARY = 'ALT' }),
    convert_keys(pane_keys, { PRIMARY = 'CTRL', SECONDARY = 'ALT' }),
    windows_specific_keys
  ),
  darwin_keys = merge_keys(
    common_keys,
    convert_keys(unified_keys, { PRIMARY = 'CTRL', SECONDARY = 'ALT' }),
    convert_keys(pane_keys, { PRIMARY = 'CTRL', SECONDARY = 'ALT' }),
    darwin_specific_keys -- macOS固有キーを最後に配置して優先
  ),
  key_tables = {
    copy_mode = copy_mode,
    search_mode = search_mode,
  },
}
