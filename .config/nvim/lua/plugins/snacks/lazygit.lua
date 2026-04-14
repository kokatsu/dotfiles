-- Lazygit設定 (palette は catppuccin の flavor に追従)
local M = {}

local ok, palettes = pcall(require, 'catppuccin.palettes')
local p = ok and palettes.get_palette()
  or {
    blue = '#89b4fa',
    subtext0 = '#a6adc8',
    surface0 = '#313244',
    surface1 = '#45475a',
    red = '#f38ba8',
    text = '#cdd6f4',
    yellow = '#f9e2af',
  }

M.opts = {
  configure = true,
  config = {
    os = { editPreset = 'nvim-remote' },
    gui = {
      nerdFontsVersion = '3',
      theme = {
        activeBorderColor = { p.blue, 'bold' },
        inactiveBorderColor = { p.subtext0 },
        optionsTextColor = { p.blue },
        selectedLineBgColor = { p.surface0 },
        cherryPickedCommitBgColor = { p.surface1 },
        cherryPickedCommitFgColor = { p.blue },
        unstagedChangesColor = { p.red },
        defaultFgColor = { p.text },
        searchingActiveBorderColor = { p.yellow },
      },
    },
  },
  theme = {
    [241] = { fg = 'Special' },
    activeBorderColor = { fg = 'MatchParen', bold = true },
    cherryPickedCommitBgColor = { fg = 'Identifier' },
    cherryPickedCommitFgColor = { fg = 'Function' },
    defaultFgColor = { fg = 'Normal' },
    inactiveBorderColor = { fg = 'FloatBorder' },
    optionsTextColor = { fg = 'Function' },
    searchingActiveBorderColor = { fg = 'MatchParen', bold = true },
    selectedLineBgColor = { bg = 'Visual' }, -- set to `default` to have no background colour
    unstagedChangesColor = { fg = 'DiagnosticError' },
  },
  win = {
    position = 'float',
  },
}

return M
