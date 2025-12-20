-- キーマップ設定

-- 挿入モードでescを押したら保存する
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

-- 日付を挿入するキーマップ
vim.keymap.set('n', '<C-k>', "\"=strftime('%Y-%m-%d %H:%M:%S')<CR>p", {
  desc = 'Insert current date and time',
  noremap = true,
})
-- 挿入モードで日付を挿入するキーマップ
vim.keymap.set('i', '<C-k>', "<C-r>=strftime('%Y-%m-%d %H:%M:%S')<CR>", {
  desc = 'Insert current date and time',
  noremap = true,
})

vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, {
  desc = 'Open diagnostic message',
  noremap = true,
  silent = true,
})

vim.keymap.set('n', 'gh', vim.lsp.buf.hover, {
  desc = 'LSP Hover',
  noremap = true,
  silent = true,
})

vim.keymap.set('n', '<leader>p', function()
  local absolute_path = vim.fn.expand('%:p')

  -- 現在の作業ディレクトリ（Neovimで開いている箇所）からの相対パスを取得
  local relative_path = vim.fn.fnamemodify(absolute_path, ':.')

  vim.fn.setreg('+', relative_path)
  vim.notify('Copied "' .. relative_path .. '" to the clipboard!')
end, { noremap = true, desc = 'Copy current file path to clipboard (relative to current directory)' })

-- 診断メッセージをクリップボードにコピーするキーマップ
vim.keymap.set('n', '<leader>c', function()
  local diagnostics = vim.diagnostic.get(0)
  local cursor_line = vim.fn.line('.')

  -- カーソル位置の診断を探す
  local current_diagnostic = nil
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.lnum == cursor_line - 1 then
      current_diagnostic = diagnostic
      break
    end
  end

  if current_diagnostic then
    local message = current_diagnostic.message
    vim.fn.setreg('+', message)
    vim.notify('診断メッセージをコピーしました: ' .. message, vim.log.levels.INFO)
  else
    vim.notify('カーソル位置に診断メッセージがありません', vim.log.levels.WARN)
  end
end, { noremap = true, desc = 'Copy diagnostic message to clipboard' })

-- すべての診断メッセージをクリップボードにコピーするキーマップ
vim.keymap.set('n', '<leader>C', function()
  local diagnostics = vim.diagnostic.get(0)
  if #diagnostics == 0 then
    vim.notify('診断メッセージがありません', vim.log.levels.INFO)
    return
  end

  local messages = {}
  for _, diagnostic in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[diagnostic.severity]:lower()
    local line = diagnostic.lnum + 1
    local message = string.format('[%s] Line %d: %s', severity, line, diagnostic.message)
    table.insert(messages, message)
  end

  local all_messages = table.concat(messages, '\n')
  vim.fn.setreg('+', all_messages)
  vim.notify(string.format('%d個の診断メッセージをコピーしました', #diagnostics), vim.log.levels.INFO)
end, { noremap = true, desc = 'Copy all diagnostic messages to clipboard' })
