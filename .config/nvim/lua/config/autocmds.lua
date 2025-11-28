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
vim.api.nvim_create_autocmd({ 'WinEnter', 'FocusGained', 'BufEnter' }, {
  pattern = '*',
  command = 'checktime',
})

local os_utils = require('utils.os')

-- WSLの場合はInsertモードから離れる時にzenhanを実行
local os_name = os_utils.detect_os()
local group = vim.api.nvim_create_augroup('kyoh86-conf-ime', {})
if os_name == 'wsl' then
  if os.getenv('WSL_DISTRO_NAME') ~= '' then
    vim.api.nvim_create_autocmd('InsertLeave', {
      group = group,
      command = 'silent! !zenhan 0',
    })
  end
end
