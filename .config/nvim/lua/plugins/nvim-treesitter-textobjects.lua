-- https://github.com/nvim-treesitter/nvim-treesitter-textobjects

return {
  'nvim-treesitter/nvim-treesitter-textobjects',
  branch = 'main',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    -- textobjects クエリ (queries/<lang>/textobjects.scm) を rtp に供給する。
    -- これにより editor.lua の ]f/[f/]c/[c (move モジュール) と
    -- mini.ai の af/ac/ap/ao (gen_spec.treesitter) が動作する。
    require('nvim-treesitter-textobjects').setup({
      move = {
        set_jumps = true, -- ジャンプリストに記録 (Ctrl-o で戻れる)
      },
    })
  end,
}
