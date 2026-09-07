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

-- editPreset / nerdFontsVersion は nix/home/programs/lazygit.nix 側の設定ファイルに
-- あり、snacks は --use-config-file でそちらも読み込むためここでは重複させない
M.opts = {
  configure = true,
  config = {
    gui = {
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
  win = {
    position = 'float',
  },
}

return M
