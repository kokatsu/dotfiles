-- https://github.com/nvim-treesitter/nvim-treesitter

return {
  name = 'nvim-treesitter',
  dir = vim.fn.stdpath('data') .. '/nix-plugins/nvim-treesitter',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    require('nvim-treesitter').setup({ install_dir = vim.fn.stdpath('data') .. '/nix-plugins/nvim-treesitter' })

    -- コードフェンスの言語エイリアス (````md → markdown パーサーを使用)
    vim.treesitter.language.register('markdown', 'md')

    -- Treesitterハイライトを全ファイルタイプで有効化
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
      end,
    })
  end,
}
