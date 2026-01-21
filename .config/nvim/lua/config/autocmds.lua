-- Autocmd設定

-- snacks_dashboardでの:qをフリーズさせない
-- GIFアニメーション(chafa)が実行中のため、:qaで強制終了する
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'snacks_dashboard',
  callback = function()
    vim.keymap.set('ca', 'q', 'qa', { buffer = true })
    vim.keymap.set('ca', 'q!', 'qa!', { buffer = true })
  end,
})

-- https://minerva.mamansoft.net/Notes/%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB%E3%81%8C%E5%A4%89%E6%9B%B4%E3%81%95%E3%82%8C%E3%81%9F%E3%82%89%E8%87%AA%E5%8B%95%E3%81%A7%E5%86%8D%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF+(Neovim)
-- 外部からファイルを変更されたら反映する
-- CursorHold/CursorHoldIを追加してClaude Code等の外部ツールによる変更を検知
vim.api.nvim_create_autocmd({ 'WinEnter', 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  pattern = '*',
  command = 'checktime',
})

-- 外部でファイルが変更された後、LSPに変更を通知して診断を更新
-- Claude Code等の外部ツールによる変更後にrust-analyzer等の診断を反映させる
vim.api.nvim_create_autocmd('FileChangedShellPost', {
  pattern = '*',
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
      local params = vim.lsp.util.make_text_document_params(bufnr)
      client:notify('textDocument/didSave', params)
    end
  end,
})

local os_utils = require('utils.os')

-- WSLの場合はInsertモードから離れる時にzenhanを実行
local os_name = os_utils.detect_os()
local group = vim.api.nvim_create_augroup('kyoh86-conf-ime', {})
if os_name == 'wsl' then
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    command = 'silent! !zenhan 0',
  })
end

-- フォーカスを失ったときにVisualモードを解除する
-- 別ペーンから戻ったときにVisualモードに気づかず操作するミスを防ぐ
vim.api.nvim_create_autocmd('FocusLost', {
  callback = function()
    local mode = vim.api.nvim_get_mode().mode
    if mode == 'v' or mode == 'V' or mode == '\22' then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    end
  end,
})
