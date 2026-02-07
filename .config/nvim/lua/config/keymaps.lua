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

-- LSP keymaps
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { desc = 'Go to declaration' })
vim.keymap.set('n', 'gr', vim.lsp.buf.references, { desc = 'References' })
vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { desc = 'Implementation' })
vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, { desc = 'Type definition' })
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'Rename symbol' })
vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code action' })
vim.keymap.set('n', '<leader>cf', function()
  vim.lsp.buf.format({ async = true })
end, { desc = 'Format buffer' })
vim.keymap.set('i', '<C-h>', vim.lsp.buf.signature_help, { desc = 'Signature help' })

-- Neovim 0.11+ デフォルトの <C-s> → signature_help を無効化（WezTerm の Ctrl+S と競合）
pcall(vim.keymap.del, { 'i', 's' }, '<C-s>')
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    pcall(vim.keymap.del, { 'i', 's' }, '<C-s>', { buffer = args.buf })
  end,
})
vim.keymap.set('n', '<leader>ds', vim.lsp.buf.document_symbol, { desc = 'Document symbols' })
vim.keymap.set('n', '<leader>ws', vim.lsp.buf.workspace_symbol, { desc = 'Workspace symbols' })

-- LSP → Trouble連携
vim.keymap.set('n', 'gR', '<cmd>Trouble lsp_references<cr>', { desc = 'References (Trouble)' })
vim.keymap.set('n', 'gI', '<cmd>Trouble lsp_implementations<cr>', { desc = 'Implementations (Trouble)' })
vim.keymap.set('n', 'gT', '<cmd>Trouble lsp_type_definitions<cr>', { desc = 'Type Definitions (Trouble)' })

-- Inlay Hints トグル
vim.keymap.set('n', '<leader>th', function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = 'Toggle Inlay Hints' })

-- Treesitterベースの移動（関数/クラス間）
local function goto_textobject(query, direction)
  return function()
    local parsers = require('nvim-treesitter.parsers')

    local bufnr = vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)
    if not lang then
      return
    end

    local parser = parsers.get_parser(bufnr, lang)
    if not parser then
      return
    end

    local tree = parser:parse()[1]
    if not tree then
      return
    end

    local root = tree:root()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_row = cursor[1] - 1

    local matches = {}
    local query_obj = vim.treesitter.query.get(lang, 'textobjects')
    if not query_obj then
      return
    end

    for id, node in query_obj:iter_captures(root, bufnr, 0, -1) do
      local name = query_obj.captures[id]
      if name == query then
        local start_row = node:start()
        table.insert(matches, { row = start_row, node = node })
      end
    end

    table.sort(matches, function(a, b)
      return a.row < b.row
    end)

    local target = nil
    if direction == 'next' then
      for _, m in ipairs(matches) do
        if m.row > cursor_row then
          target = m
          break
        end
      end
    else
      for i = #matches, 1, -1 do
        if matches[i].row < cursor_row then
          target = matches[i]
          break
        end
      end
    end

    if target then
      vim.api.nvim_win_set_cursor(0, { target.row + 1, 0 })
    end
  end
end

vim.keymap.set('n', ']f', goto_textobject('function.outer', 'next'), { desc = 'Next function' })
vim.keymap.set('n', '[f', goto_textobject('function.outer', 'prev'), { desc = 'Previous function' })
vim.keymap.set('n', ']c', goto_textobject('class.outer', 'next'), { desc = 'Next class' })
vim.keymap.set('n', '[c', goto_textobject('class.outer', 'prev'), { desc = 'Previous class' })

vim.keymap.set('n', '<leader>yp', function()
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
