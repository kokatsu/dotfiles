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

local function env_or(name, fallback)
  local value = vim.env[name]
  return value ~= nil and value ~= '' and value or fallback
end

function M.flavor()
  return env_or('CATPPUCCIN_FLAVOR', 'mocha')
end

function M.light_flavor()
  return env_or('CATPPUCCIN_NVIM_LIGHT_FLAVOR', 'latte')
end

function M.accent()
  return env_or('CATPPUCCIN_ACCENT', 'blue')
end

function M.get()
  local ok, palettes = pcall(require, 'catppuccin.palettes')
  local palette = ok and palettes.get_palette() or mocha
  return vim.tbl_extend('force', palette, { accent = palette[M.accent()] or palette.blue })
end

return M
