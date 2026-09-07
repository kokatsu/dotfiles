local os_utils = require('utils.os')

local M = {}

--- @type snacks.gitbrowse.Config
M.opts = {
  -- WSL: Open URLs in Windows browser
  open = os_utils.detect_os() == 'wsl' and function(url)
    -- gsub は置換回数も返すため括弧で 1 値に絞る (cmd.exe に余分な引数を渡さない)
    vim.fn.jobstart({ 'cmd.exe', '/c', 'start', (url:gsub('&', '^&')) }, { detach = true })
  end or nil,
}

return M
