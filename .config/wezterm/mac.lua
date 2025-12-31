local M = {}

M.apply_to_config = function(config)
  config.window_background_opacity = 0.75
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
end

return M
