local M = {}

local mocha = {
  base = '#1e1e2e',
  blue = '#89b4fa',
  crust = '#11111b',
  red = '#f38ba8',
  subtext0 = '#a6adc8',
  surface0 = '#313244',
  surface1 = '#45475a',
  text = '#cdd6f4',
  yellow = '#f9e2af',
}

function M.get()
  local ok, palettes = pcall(require, 'catppuccin.palettes')
  return ok and palettes.get_palette() or mocha
end

return M
