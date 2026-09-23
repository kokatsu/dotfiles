-- LSP keymaps
--
-- Layered design:
--   g*           : navigation (vim-native style)
--   <leader>c*   : LSP standard ops (code/lsp group)
--   <leader>l*   : language extras (per-ft, defined in plugin specs)

-- Navigation
vim.keymap.set('n', 'gh', vim.lsp.buf.hover, { desc = 'LSP Hover', noremap = true, silent = true })
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { desc = 'Go to declaration' })
vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { desc = 'Implementation' })
vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, { desc = 'Type definition' })

-- Picker
vim.keymap.set('n', 'gR', function()
  Snacks.picker.lsp_references()
end, { desc = 'References (Picker)' })
vim.keymap.set('n', 'gI', function()
  Snacks.picker.lsp_implementations()
end, { desc = 'Implementations (Picker)' })
vim.keymap.set('n', 'gT', function()
  Snacks.picker.lsp_type_definitions()
end, { desc = 'Type Definitions (Picker)' })

-- Standard ops (<leader>c*)
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code action' })
vim.keymap.set('n', '<leader>cf', function()
  vim.lsp.buf.format({ async = true })
end, { desc = 'Format buffer' })
vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename, { desc = 'Rename symbol' })
vim.keymap.set('n', '<leader>cs', vim.lsp.buf.document_symbol, { desc = 'Document symbols' })
vim.keymap.set('n', '<leader>cS', vim.lsp.buf.workspace_symbol, { desc = 'Workspace symbols' })
vim.keymap.set('n', '<leader>cd', vim.diagnostic.open_float, {
  desc = 'Diagnostic float',
  noremap = true,
  silent = true,
})
vim.keymap.set('n', '<leader>ch', function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = 'Toggle Inlay Hints' })

-- Signature help (insert mode)
vim.keymap.set('i', '<C-h>', vim.lsp.buf.signature_help, { desc = 'Signature help' })

-- Neovim 0.11+ デフォルトの <C-s> → signature_help を無効化 (Ghostty の ctrl+s と競合)
-- 既定マップはグローバルのみで LspAttach でバッファローカルには張られない
pcall(vim.keymap.del, { 'i', 's' }, '<C-s>')
