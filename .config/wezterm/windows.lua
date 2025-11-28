local wezterm = require('wezterm') --[[@as Wezterm]]

local M = {}

M.apply_to_config = function(config)
  config.window_background_opacity = 1.0
  config.font_size = 10.5

  ---@type WslDomain[]
  local wsl_domains = wezterm.default_wsl_domains()
  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = '~'
  end
  config.wsl_domains = wsl_domains
  config.default_domain = wsl_domains[1].name
  wezterm.home_dir = '~'

  local keys = require('keybinds').windows_keys
  config.keys = keys

  local background = require('background')
  background.apply_to_keys(keys, 'ALT', 'CTRL')
  config.background = background.default_background
end

return M
