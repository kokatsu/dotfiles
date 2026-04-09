-- https://github.com/apple/pkl-neovim

return {
  'apple/pkl-neovim',
  ft = 'pkl',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  build = function()
    require('pkl-neovim').init()
    require('nvim-treesitter').install({ 'pkl' })
  end,
  config = function()
    vim.g.pkl_neovim = {
      start_command = { 'pkl-lsp' },
      -- pkl-lsp の `pkl.cli.path` 設定に渡される。download_package 等の
      -- LSP コマンドで必要なため、PATH 上の pkl を明示する
      pkl_cli_path = 'pkl',
    }
  end,
}
