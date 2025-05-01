local wezterm = require('wezterm')
local act = wezterm.action

return {
  windows_keys = {
    {
      -- `Control + C` でクリップボードにコピー
      key = 'c',
      mods = 'CTRL',
      action = act.CopyTo('Clipboard'),
    },
    {
      -- `Control + Shift + C` でキャンセル
      key = 'c',
      mods = 'CTRL|SHIFT',
      action = act.SendKey({
        key = 'c',
        mods = 'CTRL',
      }),
    },
    {
      -- `Control + V` でクリップボードからペースト
      key = 'v',
      mods = 'CTRL',
      action = act.PasteFrom('Clipboard'),
    },
    {
      -- `Control + S` で水平分割
      key = 's',
      mods = 'CTRL',
      action = act.SplitHorizontal({}),
    },
    {
      -- `Control + Shift + S` で垂直分割
      key = 's',
      mods = 'CTRL|SHIFT',
      action = act.SplitVertical({}),
    },
    {
      -- `Control + T` で新しいタブを作成
      key = 't',
      mods = 'CTRL',
      action = act.SpawnCommandInNewTab({
        cwd = wezterm.home_dir,
      }),
    },
    {
      -- `Control + Shift + T` で現在のタブを新しいタブにコピー
      key = 't',
      mods = 'CTRL|SHIFT',
      action = act.SpawnTab('CurrentPaneDomain'),
    },
    {
      -- `Control + N` で新しいウィンドウを作成
      key = 'n',
      mods = 'CTRL',
      action = act.SpawnCommandInNewWindow({
        cwd = wezterm.home_dir,
      }),
    },
    {
      -- `Control + Shift + N` で現在のウィンドウを新しいウィンドウにコピー
      key = 'n',
      mods = 'CTRL|SHIFT',
      action = act.SpawnWindow,
    },
    {
      -- `Control + W` で現在のペインを閉じる(確認ダイアログを表示)
      key = 'w',
      mods = 'CTRL',
      action = act.CloseCurrentPane({ confirm = true }),
    },
    {
      -- `Control + Shift + W` で現在のペインを閉じる(確認ダイアログを表示しない)
      key = 'w',
      mods = 'CTRL|SHIFT',
      action = act.CloseCurrentPane({ confirm = false }),
    },
    {
      -- `Alt + 左矢印` で左のペインに移動
      key = 'LeftArrow',
      mods = 'ALT',
      action = act.ActivatePaneDirection('Left'),
    },
    {
      -- `Alt + 右矢印` で右のペインに移動
      key = 'RightArrow',
      mods = 'ALT',
      action = act.ActivatePaneDirection('Right'),
    },
    {
      -- `Alt + 上矢印` で上のペインに移動
      key = 'UpArrow',
      mods = 'ALT',
      action = act.ActivatePaneDirection('Up'),
    },
    {
      -- `Alt + 下矢印` で下のペインに移動
      key = 'DownArrow',
      mods = 'ALT',
      action = act.ActivatePaneDirection('Down'),
    },
    {
      -- `Control + Tab` で右のタブに移動
      key = 'Tab',
      mods = 'CTRL',
      action = act.ActivateTabRelative(1),
    },
    {
      -- `Control + Shift + Tab` で左のタブに移動
      key = 'Tab',
      mods = 'CTRL|SHIFT',
      action = act.ActivateTabRelative(-1),
    },
    {
      -- `Control + 左矢印` で前の単語に移動
      key = 'LeftArrow',
      mods = 'CTRL',
      action = act.SendKey({
        key = 'b',
        mods = 'META',
      }),
    },
    {
      -- `Control + 右矢印` で次の単語に移動
      key = 'RightArrow',
      mods = 'CTRL',
      action = act.SendKey({
        key = 'f',
        mods = 'META',
      }),
    },
    {
      -- `Control + Shift + L` でデバッグオーバーレイを表示
      key = 'l',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.ShowDebugOverlay,
    },
    {
      -- `Control + ;` でフォントを大きくする
      key = ';',
      mods = 'CTRL',
      action = act.IncreaseFontSize,
    },
    {
      -- `Control + -` でフォントを小さくする
      key = '-',
      mods = 'CTRL',
      action = act.DecreaseFontSize,
    },
    {
      -- `Control + :` でフォントをリセット
      key = ':',
      mods = 'CTRL',
      action = act.ResetFontSize,
    },
    {
      -- `Control + [` でタブを左に移動
      key = '[',
      mods = 'CTRL',
      action = act.MoveTabRelative(-1),
    },
    {
      -- `Control + ]` でタブを右に移動
      key = ']',
      mods = 'CTRL',
      action = act.MoveTabRelative(1),
    },
    {
      -- `Control + Backspace` で単語を削除
      -- https://github.com/wezterm/wezterm/discussions/3983
      -- https://github.com/wezterm/wezterm/discussions/3983#discussioncomment-6981806
      key = 'Backspace',
      mods = 'CTRL',
      action = act.SendKey({
        key = 'w',
        mods = 'CTRL',
      }),
    },
  },

  darwin_keys = {
    {
      key = 'c',
      mods = 'CMD',
      action = act.SendKey({
        key = 'c',
        mods = 'CMD',
      }),
    },
    {
      key = 'c',
      mods = 'CMD|SHIFT',
      action = act.CopyTo('Clipboard'),
    },
    {
      key = 'v',
      mods = 'CMD',
      action = act.PasteFrom('Clipboard'),
    },
    {
      key = 's',
      mods = 'CTRL',
      action = act.SplitHorizontal({}),
    },
    {
      key = 's',
      mods = 'CTRL|SHIFT',
      action = act.SplitVertical({}),
    },
    {
      key = 't',
      mods = 'CTRL',
      action = act.SpawnCommandInNewTab({
        cwd = wezterm.home_dir,
      }),
    },
    {
      key = 't',
      mods = 'CTRL|SHIFT',
      action = act.SpawnTab('CurrentPaneDomain'),
    },
    {
      key = 'n',
      mods = 'CTRL',
      action = act.SpawnCommandInNewWindow({
        cwd = wezterm.home_dir,
      }),
    },
    {
      key = 'n',
      mods = 'CTRL|SHIFT',
      action = act.SpawnWindow,
    },
    {
      key = 'w',
      mods = 'CTRL',
      action = act.CloseCurrentPane({ confirm = false }),
    },
    {
      key = 'LeftArrow',
      mods = 'CTRL',
      action = act.ActivatePaneDirection('Left'),
    },
    {
      key = 'RightArrow',
      mods = 'CTRL',
      action = act.ActivatePaneDirection('Right'),
    },
    {
      key = 'UpArrow',
      mods = 'CTRL',
      action = act.ActivatePaneDirection('Up'),
    },
    {
      key = 'DownArrow',
      mods = 'CTRL',
      action = act.ActivatePaneDirection('Down'),
    },
    {
      -- `Control + Tab` で右のタブに移動
      key = 'Tab',
      mods = 'CTRL',
      action = act.ActivateTabRelative(1),
    },
    {
      -- `Control + Shift + Tab` で左のタブに移動
      key = 'Tab',
      mods = 'CTRL|SHIFT',
      action = act.ActivateTabRelative(-1),
    },
    {
      key = 'LeftArrow',
      mods = 'CTRL',
      action = act.SendKey({
        key = 'b',
        mods = 'META',
      }),
    },
    {
      key = 'RightArrow',
      mods = 'CTRL',
      action = act.SendKey({
        key = 'f',
        mods = 'META',
      }),
    },
    {
      key = 'l',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.ShowDebugOverlay,
    },
  },
}
