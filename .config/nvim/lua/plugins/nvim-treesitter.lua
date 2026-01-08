-- https://github.com/nvim-treesitter/nvim-treesitter

return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  opts = {
    auto_install = true,
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
  },
}
