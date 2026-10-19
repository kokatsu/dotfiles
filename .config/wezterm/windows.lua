---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

local M = {}

M.apply_to_config = function(config)
  config.front_end = 'WebGpu' -- GPU アクセラレーションで描画高速化
  config.window_background_opacity = 1.0
  -- PlemolJP は UDEV Gothic より字面が大きく見えるので 10.5 から少し下げている
  config.font_size = 10.25

  ---@type WslDomain[]
  local wsl_domains = wezterm.default_wsl_domains()
  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = '~'
  end
  config.wsl_domains = wsl_domains
  config.default_domain = wsl_domains[1].name
  config.set_environment_variables = {
    WSLENV = 'WEZTERM_PANE',
  }
  local keybinds = require('keybinds')
  local keys = keybinds.windows_keys
  config.keys = keys
  config.key_tables = keybinds.key_tables

  local background = require('background')
  background.apply_to_keys(keys, 'CTRL|SHIFT', 'CTRL|SHIFT')
  config.background = background.default_background
end

return M
