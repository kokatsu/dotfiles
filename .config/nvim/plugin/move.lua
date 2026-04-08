-- Move lines/selections with Alt+hjkl (replaces mini.move)

-- Vertical: move lines up/down
vim.keymap.set('n', '<M-j>', '<cmd>silent! m .+1<CR>==', { desc = 'Move line down' })
vim.keymap.set('n', '<M-k>', '<cmd>silent! m .-2<CR>==', { desc = 'Move line up' })
vim.keymap.set('x', '<M-j>', ":silent! m '>+1<CR>gv=gv", { desc = 'Move selection down' })
vim.keymap.set('x', '<M-k>', ":silent! m '<-2<CR>gv=gv", { desc = 'Move selection up' })

-- Horizontal: indent/dedent
vim.keymap.set('n', '<M-h>', '<<', { desc = 'Move line left' })
vim.keymap.set('n', '<M-l>', '>>', { desc = 'Move line right' })
vim.keymap.set('x', '<M-h>', '<gv', { desc = 'Move selection left' })
vim.keymap.set('x', '<M-l>', '>gv', { desc = 'Move selection right' })
