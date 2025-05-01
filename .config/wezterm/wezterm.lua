local wezterm = require('wezterm')

local is_windows = wezterm.target_triple == 'x86_64-pc-windows-msvc'
local is_mac = wezterm.target_triple == 'x86_64-apple-darwin' or wezterm.target_triple == 'aarch64-apple-darwin'

local config = wezterm.config_builder()

config.automatically_reload_config = true
config.use_ime = true
config.color_scheme = 'Catppuccin Mocha'

-- https://stackoverflow.com/questions/78738575/how-to-maximize-wezterm-on-startup
wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

if is_windows then
  config.window_background_opacity = 1.0
  local wsl_domains = wezterm.default_wsl_domains()
  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = '~'
  end
  config.wsl_domains = wsl_domains
  config.default_domain = 'WSL:Ubuntu'
  wezterm.home_dir = '~'
else
  config.window_background_opacity = 0.75
end

local keybinds = require('keybinds')
if is_windows then
  config.disable_default_key_bindings = true
  config.keys = keybinds.windows_keys
elseif is_mac then
  config.disable_default_key_bindings = true
  config.keys = keybinds.darwin_keys
end

config.font = wezterm.font_with_fallback({
  'Firge35Nerd Console',
})

if is_windows then
  config.font_size = 10.5
elseif is_mac then
  config.font_size = 14
end

require('format')

local bar = wezterm.plugin.require('https://github.com/adriankarlen/bar.wezterm')
bar.apply_to_config(config)

return config
