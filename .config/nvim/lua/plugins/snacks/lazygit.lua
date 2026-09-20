-- Lazygit設定 (palette は catppuccin の flavor に追従)
local M = {}

local p = require('utils.palette').get()

-- editPreset / nerdFontsVersion は nix/home/programs/lazygit.nix 側の設定ファイルに
-- あり、snacks は --use-config-file でそちらも読み込むためここでは重複させない
M.opts = {
  configure = true,
  config = {
    gui = {
      theme = {
        activeBorderColor = { p.accent, 'bold' },
        inactiveBorderColor = { p.subtext0 },
        optionsTextColor = { p.accent },
        selectedLineBgColor = { p.surface0 },
        cherryPickedCommitBgColor = { p.surface1 },
        cherryPickedCommitFgColor = { p.accent },
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
