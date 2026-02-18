-- https://github.com/nvim-treesitter/nvim-treesitter

return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    -- macOS: パーサー.soのコード署名を検証/修復 (SIGKILL防止)
    -- Nixのtree-sitter CLIでコンパイルされたパーサーがmacOSのランタイム
    -- コード署名検証に失敗することがあるため、ロード前に再署名する
    if vim.fn.has('mac') == 1 then
      local parser_dir = vim.fn.stdpath('data') .. '/site/parser'
      vim.fn.system(
        'for f in "' .. parser_dir .. '"/*.so; do codesign -v "$f" 2>/dev/null || codesign --force --sign - "$f"; done'
      )
    end

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
