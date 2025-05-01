-- https://github.com/neovim/nvim-lspconfig

return {
  'neovim/nvim-lspconfig',
  dependencies = {
    { 'williamboman/mason.nvim', config = true, event = 'VeryLazy' },
    { 'williamboman/mason-lspconfig.nvim', event = 'VeryLazy' },
  },
}
