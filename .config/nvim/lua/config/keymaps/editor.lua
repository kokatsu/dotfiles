-- 基本編集キーマップ

-- 挿入モードで ESC: stopinsert + 自動保存
vim.keymap.set('i', '<ESC>', function()
  vim.cmd('stopinsert')
  if vim.bo.modifiable and not vim.bo.readonly and vim.bo.buftype == '' then
    vim.cmd('silent! write')
  end
end, {
  desc = 'Save file and exit insert mode',
  noremap = true,
  silent = true,
})

-- 日付時刻挿入
vim.keymap.set('n', '<C-k>', "\"=strftime('%Y-%m-%d %H:%M:%S')<CR>p", {
  desc = 'Insert current date and time',
  noremap = true,
})
vim.keymap.set('i', '<C-k>', "<C-r>=strftime('%Y-%m-%d %H:%M:%S')<CR>", {
  desc = 'Insert current date and time',
  noremap = true,
})

-- Treesitter ベースの関数/クラス間移動 (nvim-treesitter-textobjects の move モジュール)
vim.keymap.set('n', ']f', function()
  require('nvim-treesitter-textobjects.move').goto_next_start('@function.outer', 'textobjects')
end, { desc = 'Next function' })
vim.keymap.set('n', '[f', function()
  require('nvim-treesitter-textobjects.move').goto_previous_start('@function.outer', 'textobjects')
end, { desc = 'Previous function' })
vim.keymap.set('n', ']c', function()
  require('nvim-treesitter-textobjects.move').goto_next_start('@class.outer', 'textobjects')
end, { desc = 'Next class' })
vim.keymap.set('n', '[c', function()
  require('nvim-treesitter-textobjects.move').goto_previous_start('@class.outer', 'textobjects')
end, { desc = 'Previous class' })

-- Quickfix リスト内移動
vim.keymap.set('n', ']q', '<cmd>cnext<cr>zz', { desc = 'Next quickfix item' })
vim.keymap.set('n', '[q', '<cmd>cprevious<cr>zz', { desc = 'Previous quickfix item' })
