local wezterm = require('wezterm')

local M = {}

M.apply_to_config = function(config)
  config.front_end = 'WebGpu'
  config.window_background_opacity = 0.75
  -- config.macos_window_background_blur = 20
  config.font_size = 14
  -- OptionキーをAlt/Metaとして扱う（IME入力時は除く）
  config.send_composed_key_when_left_alt_is_pressed = false
  config.send_composed_key_when_right_alt_is_pressed = false

  local keybinds = require('keybinds')
  local keys = keybinds.darwin_keys
  config.keys = keys
  config.key_tables = keybinds.key_tables

  local background = require('background')
  background.apply_to_keys(keys, 'CMD', 'OPT')
  config.background = background.default_background

  config.mouse_bindings = {
    -- シングルクリックではリンクを開かない（デフォルト動作を上書き）
    {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'NONE',
      action = wezterm.action.CompleteSelection('ClipboardAndPrimarySelection'),
    },
    -- ダブルクリックでリンクを開く
    {
      event = { Up = { streak = 2, button = 'Left' } },
      mods = 'NONE',
      action = wezterm.action.OpenLinkAtMouseCursor,
    },
  }
end

return M
