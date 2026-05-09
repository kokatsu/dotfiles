-- https://github.com/clabby/difftastic.nvim

return {
  'clabby/difftastic.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'folke/snacks.nvim',
  },
  cmd = { 'Difft', 'DifftClose', 'DifftPick', 'DifftPickRange' },
  keys = {
    { '<leader>gd', '<cmd>Difft<cr>', desc = 'Diff (working tree)' },
    { '<leader>gD', '<cmd>Difft main..HEAD<cr>', desc = 'Diff vs main' },
    { '<leader>gH', '<cmd>DifftPick<cr>', desc = 'Pick revision' },
    { '<leader>gq', '<cmd>DifftClose<cr>', desc = 'Close Diff' },
  },
  opts = {
    -- difftastic は Nix で管理しているので自動ダウンロードは不要
    download = false,
    vcs = 'git',
    highlight_mode = 'treesitter',
    snacks_picker = { enabled = true },
  },
  config = function(_, opts)
    require('difftastic-nvim').setup(opts)
  end,
}
