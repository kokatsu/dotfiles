local wezterm = require('wezterm') --[[@as Wezterm]]
local act = wezterm.action

wezterm.on('maximize-window', function(window, _)
  window:maximize()
end)

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
  -- `Control + s` で水平分割
  { key = 's', mods = 'CTRL', action = act.SplitHorizontal({}) },
  -- `Control + t` で新しいタブを作成
  { key = 't', mods = 'CTRL', action = act.SpawnCommandInNewTab({ cwd = wezterm.home_dir }) },
  -- `Control + n` で新しいウィンドウを作成
  { key = 'n', mods = 'CTRL', action = act.SpawnCommandInNewWindow({ cwd = wezterm.home_dir }) },
  -- `Control + Tab` で右のタブに移動
  { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
  -- `Control + Shift + Tab` で左のタブに移動
  { key = 'Tab', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
  -- `Shift + Enter` で 改行を送信
  -- https://zenn.dev/glaucus03/articles/070589323cb450
  { key = 'Enter', mods = 'SHIFT', action = act.SendString('\n') },
  -- `Control + z` でペインをズーム（トグル）
  { key = 'z', mods = 'CTRL', action = act.TogglePaneZoomState },
}

-- Windows 固有キーバインド
local windows_specific_keys = {
  -- `Control + C` でクリップボードにコピー
  { key = 'c', mods = 'CTRL', action = act.CopyTo('Clipboard') },
  -- `Control + C` でキャンセル
  { key = 'C', mods = 'CTRL', action = act.SendKey({ key = 'c', mods = 'CTRL' }) },
  -- `Control + V` でクリップボードからペースト
  { key = 'v', mods = 'CTRL', action = act.PasteFrom('Clipboard') },
  -- `Control + S` で垂直分割
  { key = 'S', mods = 'CTRL', action = act.SplitVertical({}) },
  -- `Control + T` で現在のタブを新しいタブにコピー
  { key = 'T', mods = 'CTRL', action = act.SpawnTab('CurrentPaneDomain') },
  -- `Control + N` で現在のウィンドウを新しいウィンドウにコピー
  { key = 'N', mods = 'CTRL', action = act.SpawnWindow },
  -- `Alt + w` で現在のペインを閉じる(確認ダイアログを表示しない)
  { key = 'w', mods = 'ALT', action = act.CloseCurrentPane({ confirm = false }) },
  -- `Alt + 左矢印` で左のペインに移動
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection('Left') },
  -- `Alt + 右矢印` で右のペインに移動
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection('Right') },
  -- `Alt + 上矢印` で上のペインに移動
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection('Up') },
  -- `Alt + 下矢印` で下のペインに移動
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection('Down') },
  -- `Control + 左矢印` で前の単語に移動
  -- selene: allow(bad_string_escape)
  { key = 'LeftArrow', mods = 'CTRL', action = act.SendString('\x1b[1;5D') },
  -- `Control + 右矢印` で次の単語に移動
  -- selene: allow(bad_string_escape)
  { key = 'RightArrow', mods = 'CTRL', action = act.SendString('\x1b[1;5C') },
  -- `Control + L` でデバッグオーバーレイを表示
  { key = 'L', mods = 'CTRL', action = act.ShowDebugOverlay },
  -- `Control + ;` でフォントを大きくする
  { key = ';', mods = 'CTRL', action = act.IncreaseFontSize },
  -- `Control + -` でフォントを小さくする
  { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
  -- `Control + :` でフォントをリセット
  { key = ':', mods = 'CTRL', action = act.ResetFontSize },
  -- `Control + [` でタブを左に移動
  { key = '[', mods = 'CTRL', action = act.MoveTabRelative(-1) },
  -- `Control + ]` でタブを右に移動
  { key = ']', mods = 'CTRL', action = act.MoveTabRelative(1) },
  -- `Control + Backspace` で単語を削除
  -- https://github.com/wezterm/wezterm/discussions/3983
  -- https://github.com/wezterm/wezterm/discussions/3983#discussioncomment-6981806
  { key = 'Backspace', mods = 'CTRL', action = act.SendKey({ key = 'w', mods = 'CTRL' }) },
  -- `Control + 1` で左から1番目のタブに移動
  { key = '1', mods = 'CTRL', action = act.ActivateTab(0) },
  -- `Control + 2` で左から2番目のタブに移動
  { key = '2', mods = 'CTRL', action = act.ActivateTab(1) },
  -- `Control + 3` で左から3番目のタブに移動
  { key = '3', mods = 'CTRL', action = act.ActivateTab(2) },
  -- `Control + 4` で左から4番目のタブに移動
  { key = '4', mods = 'CTRL', action = act.ActivateTab(3) },
  -- `Control + 5` で左から5番目のタブに移動
  { key = '5', mods = 'CTRL', action = act.ActivateTab(4) },
  -- `Control + 6` で左から6番目のタブに移動
  { key = '6', mods = 'CTRL', action = act.ActivateTab(5) },
  -- `Control + 7` で左から7番目のタブに移動
  { key = '7', mods = 'CTRL', action = act.ActivateTab(6) },
  -- `Control + 8` で左から8番目のタブに移動
  { key = '8', mods = 'CTRL', action = act.ActivateTab(7) },
  -- `Control + 9` で最後のタブに移動
  { key = '9', mods = 'CTRL', action = act.ActivateLastTab },
  -- `Control + Shift + 左矢印` でペインを左に拡大
  { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize({ 'Left', 1 }) },
  -- `Control + Shift + 右矢印` でペインを右に拡大
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize({ 'Right', 1 }) },
  -- `Control + Shift + 上矢印` でペインを上に拡大
  { key = 'UpArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize({ 'Up', 1 }) },
  -- `Control + Shift + 下矢印` でペインを下に拡大
  { key = 'DownArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize({ 'Down', 1 }) },
  -- https://wezterm.org/config/lua/keyassignment/RotatePanes.html
  -- `Alt + l` でペインを左に回転
  { key = 'l', mods = 'ALT', action = act.RotatePanes('CounterClockwise') },
  -- `Alt + r` でペインを右に回転
  { key = 'r', mods = 'ALT', action = act.RotatePanes('Clockwise') },
  -- `Control + X` でコピーモードをアクティブにする
  { key = 'X', mods = 'CTRL', action = act.ActivateCopyMode },
  -- `Alt + f` で画面を最大化
  { key = 'f', mods = 'ALT', action = act.EmitEvent('maximize-window') },
  -- `Alt + y` で新しいタブで PowerShell を起動
  {
    key = 'y',
    mods = 'ALT',
    action = act.SpawnCommandInNewTab({ args = { 'powershell.exe' }, domain = { DomainName = 'local' } }),
  },
  -- QuickSelect モード（URLやパスを素早く選択）
  { key = 'q', mods = 'ALT', action = act.QuickSelect },
}

-- macOS 固有キーバインド
local darwin_specific_keys = {
  -- `Control + x` でコピーモードをアクティブにする
  { key = 'x', mods = 'CTRL', action = act.ActivateCopyMode },
  -- `Command + c` でシェルに Ctrl+C (SIGINT) を送信
  { key = 'c', mods = 'CMD', action = act.SendKey({ key = 'c', mods = 'CTRL' }) },
  -- `Command + Shift + c` でクリップボードにコピー
  { key = 'c', mods = 'CMD|SHIFT', action = act.CopyTo('Clipboard') },
  -- `Command + v` でクリップボードからペースト
  { key = 'v', mods = 'CMD', action = act.PasteFrom('Clipboard') },
  -- `Control + Shift + s` で垂直分割
  { key = 's', mods = 'CTRL|SHIFT', action = act.SplitVertical({}) },
  -- `Control + Shift + t` で現在のタブを新しいタブにコピー
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab('CurrentPaneDomain') },
  -- `Control + Shift + n` で現在のウィンドウを新しいウィンドウにコピー
  { key = 'n', mods = 'CTRL|SHIFT', action = act.SpawnWindow },
  -- `Control + w` で現在のペインを閉じる(確認ダイアログを表示しない)
  { key = 'w', mods = 'CTRL', action = act.CloseCurrentPane({ confirm = false }) },
  -- `Command + Option + 左矢印` で左のペインに移動
  { key = 'LeftArrow', mods = 'CMD|OPT', action = act.ActivatePaneDirection('Left') },
  -- `Command + Option + 右矢印` で右のペインに移動
  { key = 'RightArrow', mods = 'CMD|OPT', action = act.ActivatePaneDirection('Right') },
  -- `Command + Option + 上矢印` で上のペインに移動
  { key = 'UpArrow', mods = 'CMD|OPT', action = act.ActivatePaneDirection('Up') },
  -- `Command + Option + 下矢印` で下のペインに移動
  { key = 'DownArrow', mods = 'CMD|OPT', action = act.ActivatePaneDirection('Down') },
  -- `Option + 左矢印` で前の単語に移動 (Esc+b)
  -- selene: allow(bad_string_escape)
  { key = 'LeftArrow', mods = 'OPT', action = act.SendString('\x1bb') },
  -- `Option + 右矢印` で次の単語に移動 (Esc+f)
  -- selene: allow(bad_string_escape)
  { key = 'RightArrow', mods = 'OPT', action = act.SendString('\x1bf') },
  -- `Control + 左矢印` で前の単語に移動
  -- selene: allow(bad_string_escape)
  { key = 'LeftArrow', mods = 'CTRL', action = act.SendString('\x1b[1;5D') },
  -- `Control + 右矢印` で次の単語に移動
  -- selene: allow(bad_string_escape)
  { key = 'RightArrow', mods = 'CTRL', action = act.SendString('\x1b[1;5C') },
  -- `Option + Backspace` で前の単語を削除
  { key = 'Backspace', mods = 'OPT', action = act.SendKey({ key = 'w', mods = 'CTRL' }) },
  -- `Control + Shift + l` でデバッグオーバーレイを表示
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowDebugOverlay },
  -- `Control + f` で画面を最大化
  { key = 'f', mods = 'CTRL', action = act.EmitEvent('maximize-window') },
  -- タブ切替 Cmd + 数字
  { key = '1', mods = 'CMD', action = act.ActivateTab(0) },
  { key = '2', mods = 'CMD', action = act.ActivateTab(1) },
  { key = '3', mods = 'CMD', action = act.ActivateTab(2) },
  { key = '4', mods = 'CMD', action = act.ActivateTab(3) },
  { key = '5', mods = 'CMD', action = act.ActivateTab(4) },
  { key = '6', mods = 'CMD', action = act.ActivateTab(5) },
  { key = '7', mods = 'CMD', action = act.ActivateTab(6) },
  { key = '8', mods = 'CMD', action = act.ActivateTab(7) },
  { key = '9', mods = 'CMD', action = act.ActivateTab(-1) },
  -- フォントサイズ調整
  { key = '+', mods = 'CMD', action = act.IncreaseFontSize },
  { key = '-', mods = 'CMD', action = act.DecreaseFontSize },
  { key = '0', mods = 'CMD', action = act.ResetFontSize },
  -- タブ順序変更
  { key = '[', mods = 'CMD|SHIFT', action = act.MoveTabRelative(-1) },
  { key = ']', mods = 'CMD|SHIFT', action = act.MoveTabRelative(1) },
  -- ペインリサイズ
  { key = 'LeftArrow', mods = 'CMD|SHIFT', action = act.AdjustPaneSize({ 'Left', 1 }) },
  { key = 'RightArrow', mods = 'CMD|SHIFT', action = act.AdjustPaneSize({ 'Right', 1 }) },
  { key = 'UpArrow', mods = 'CMD|SHIFT', action = act.AdjustPaneSize({ 'Up', 1 }) },
  { key = 'DownArrow', mods = 'CMD|SHIFT', action = act.AdjustPaneSize({ 'Down', 1 }) },
  -- ペイン回転
  { key = 'l', mods = 'CMD|OPT', action = act.RotatePanes('CounterClockwise') },
  { key = 'r', mods = 'CMD|OPT', action = act.RotatePanes('Clockwise') },
  -- QuickSelect モード（URLやパスを素早く選択）
  { key = 'q', mods = 'CTRL', action = act.QuickSelect },
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
  windows_keys = merge_keys(common_keys, windows_specific_keys),
  darwin_keys = merge_keys(common_keys, darwin_specific_keys),
  key_tables = {
    copy_mode = copy_mode,
    search_mode = search_mode,
  },
}
