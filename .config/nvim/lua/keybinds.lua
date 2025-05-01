-- 日付を挿入するキーマップ
vim.keymap.set('n', '<C-K>', "\"=strftime('%Y-%m-%d %H:%M:%S')<CR>p", { noremap = true })
-- 挿入モードで日付を挿入するキーマップ
vim.keymap.set('i', '<C-K>', "<C-r>=strftime('%Y-%m-%d %H:%M:%S')<CR>", { noremap = true })

-- uuidgenを実行してUUIDを挿入する
-- UUIDを挿入するキーマップ
vim.keymap.set('n', '<C-D>', "\"=system('uuidgen')<CR>p", { noremap = true })
-- 挿入モードでUUIDを挿入するキーマップ
vim.keymap.set('i', '<C-D>', "<C-r>=system('uuidgen')<CR>", { noremap = true })

-- 挿入モードでescを押したら保存する
vim.keymap.set('i', '<ESC>', '<ESC>:<C-u>w<CR>', { noremap = true })
