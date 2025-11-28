local M = {}

M.apply_to_config = function(config)
  config.window_background_opacity = 0.75
  config.font_size = 14

  local keys = require('keybinds').darwin_keys
  config.keys = keys

  local background = require('background')
  background.apply_to_keys(keys, 'CMD', 'OPT')
  config.background = background.default_background
end

return M
