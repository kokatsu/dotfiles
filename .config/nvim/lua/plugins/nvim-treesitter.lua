-- https://github.com/nvim-treesitter/nvim-treesitter

return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter').setup({})

    -- パーサーのインストール
    require('nvim-treesitter').install({
      'bash',
      'css',
      'html',
      'javascript',
      'json',
      'lua',
      'markdown',
      'markdown_inline',
      'mermaid',
      'ruby',
      'rust',
      'scss',
      'sql',
      'svelte',
      'tsx',
      'typescript',
      'vim',
      'vue',
      'yaml',
    })

    -- Treesitterハイライトを全ファイルタイプで有効化
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
      end,
    })
  end,
}
