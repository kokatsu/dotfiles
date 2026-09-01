-- https://github.com/nvim-treesitter/nvim-treesitter

return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    require('nvim-treesitter').setup({})

    -- コードフェンスの言語エイリアス (````md → markdown パーサーを使用)
    vim.treesitter.language.register('markdown', 'md')

    -- Treesitterハイライトを全ファイルタイプで有効化
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
      end,
    })

    -- パーサーのインストール（VeryLazy で遅延実行し起動時のイベントループ占有を回避）
    vim.api.nvim_create_autocmd('User', {
      pattern = 'VeryLazy',
      once = true,
      callback = function()
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
      end,
    })
  end,
}
