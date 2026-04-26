-- 補助系キーマップ (translate / yank path / diagnostic copy)

-- 翻訳: <leader>R は normal/visual 共通
vim.keymap.set('n', '<leader>R', function()
  require('utils.translate').translate_comment()
end, { desc = 'Translate comment under cursor' })
vim.keymap.set('v', '<leader>R', function()
  require('utils.translate').translate_visual()
end, { desc = 'Translate visual selection' })

-- カレントファイルパス (cwd 相対) をクリップボードへ
vim.keymap.set('n', '<leader>yp', function()
  local absolute_path = vim.fn.expand('%:p')
  local relative_path = vim.fn.fnamemodify(absolute_path, ':.')
  vim.fn.setreg('+', relative_path)
  vim.notify('Copied "' .. relative_path .. '" to the clipboard!')
end, { noremap = true, desc = 'Copy current file path to clipboard (relative to cwd)' })

-- カーソル位置の診断メッセージをクリップボードへ
vim.keymap.set('n', '<leader>yd', function()
  local diagnostics = vim.diagnostic.get(0)
  local cursor_line = vim.fn.line('.')

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
end, { noremap = true, desc = 'Copy diagnostic at cursor' })

-- バッファ内全診断メッセージをクリップボードへ
vim.keymap.set('n', '<leader>yD', function()
  local diagnostics = vim.diagnostic.get(0)
  if #diagnostics == 0 then
    vim.notify('診断メッセージがありません', vim.log.levels.INFO)
    return
  end

  local messages = {}
  for _, diagnostic in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[diagnostic.severity]:lower()
    local line = diagnostic.lnum + 1
    local source = diagnostic.source or 'unknown'
    local message = string.format('%s: [%s] Line %d: %s', source, severity, line, diagnostic.message)
    table.insert(messages, message)
  end

  local all_messages = table.concat(messages, '\n')
  vim.fn.setreg('+', all_messages)
  vim.notify(string.format('%d個の診断メッセージをコピーしました', #diagnostics), vim.log.levels.INFO)
end, { noremap = true, desc = 'Copy all diagnostics in buffer' })
