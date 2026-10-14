-- https://github.com/apple/pkl-neovim

return {
  name = 'pkl-neovim',
  dir = vim.fn.stdpath('data') .. '/nix-plugins/pkl-neovim',
  ft = 'pkl',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    vim.g.pkl_neovim = {
      start_command = { 'pkl-lsp' },
      -- pkl-lsp の `pkl.cli.path` 設定に渡される。download_package 等の
      -- LSP コマンドで必要なため、PATH 上の pkl を明示する
      pkl_cli_path = 'pkl',
    }
  end,
}
