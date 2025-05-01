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
