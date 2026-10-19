-- https://github.com/nvim-treesitter/nvim-treesitter-textobjects

return {
  'nvim-treesitter/nvim-treesitter-textobjects',
  branch = 'main',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  -- textobjects クエリ (queries/<lang>/textobjects.scm) を rtp に供給する。
  -- これにより editor.lua の ]f/[f/]C/[C (move モジュール) と
  -- mini.ai の af/ac/ap/ao (gen_spec.treesitter) が動作する。
  event = { 'BufReadPre', 'BufNewFile' },
}
