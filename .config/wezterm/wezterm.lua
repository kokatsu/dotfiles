---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

local is_windows = wezterm.target_triple == 'x86_64-pc-windows-msvc'
local is_mac = wezterm.target_triple == 'x86_64-apple-darwin' or wezterm.target_triple == 'aarch64-apple-darwin'

local config = wezterm.config_builder()

config.audible_bell = 'Disabled'
config.visual_bell = {
  fade_in_duration_ms = 0,
  fade_out_duration_ms = 0,
}
config.notification_handling = 'AlwaysShow'
config.automatically_reload_config = true
config.disable_default_key_bindings = true
config.scrollback_lines = 10000
config.font = wezterm.font_with_fallback({
  'Firge35Nerd Console',
  'HackGen35 Console NF',
})
config.tab_bar_at_bottom = true
config.tab_max_width = 32
config.use_dead_keys = false
config.use_fancy_tab_bar = false
config.use_ime = true
config.window_decorations = 'RESIZE'
config.hide_tab_bar_if_only_one_tab = true

-- https://stackoverflow.com/questions/78738575/how-to-maximize-wezterm-on-startup
wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

local format = require('format')
format.apply()

local colors = require('colors')
colors.apply_to_config(config)

if is_windows then
  require('windows').apply_to_config(config)
elseif is_mac then
  require('mac').apply_to_config(config)
end

return config
