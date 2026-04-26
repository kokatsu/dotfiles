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

-- Treesitter ベースの関数/クラス間移動
local ts_motion = require('utils.ts_motion')
vim.keymap.set('n', ']f', ts_motion.goto_textobject('function.outer', 'next'), { desc = 'Next function' })
vim.keymap.set('n', '[f', ts_motion.goto_textobject('function.outer', 'prev'), { desc = 'Previous function' })
vim.keymap.set('n', ']c', ts_motion.goto_textobject('class.outer', 'next'), { desc = 'Next class' })
vim.keymap.set('n', '[c', ts_motion.goto_textobject('class.outer', 'prev'), { desc = 'Previous class' })
