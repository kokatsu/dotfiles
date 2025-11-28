-- https://github.com/nvim-treesitter/nvim-treesitter

return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter.configs').setup({
      modules = {},
      sync_install = false,
      ignore_install = {},
      auto_install = false,
      ensure_installed = {
        'css',
        'javascript',
        'json',
        'lua',
        'markdown',
        'markdown_inline',
        'mermaid',
        'rust',
        'sql',
        'svelte',
        'tsx',
        'typescript',
        'vim',
        'vue',
      },
      highlight = {
        enable = true,
      },
    })
  end,
}
