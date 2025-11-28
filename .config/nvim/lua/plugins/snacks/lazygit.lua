-- Lazygit設定
local M = {}

M.opts = {
  configure = true,
  config = {
    os = { editPreset = 'nvim-remote' },
    gui = {
      nerdFontsVersion = '3',
      theme = {
        activeBorderColor = {
          '#89b4fa',
          'bold',
        },
        inactiveBorderColor = {
          '#a6adc8',
        },
        optionsTextColor = {
          '#89b4fa',
        },
        selectedLineBgColor = {
          '#313244',
        },
        cherryPickedCommitBgColor = {
          '#45475a',
        },
        cherryPickedCommitFgColor = {
          '#89b4fa',
        },
        unstagedChangesColor = {
          '#f38ba8',
        },
        defaultFgColor = {
          '#cdd6f4',
        },
        searchingActiveBorderColor = {
          '#f9e2af',
        },
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
