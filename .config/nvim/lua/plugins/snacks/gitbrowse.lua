local os_utils = require('utils.os')

local M = {}

--- @type snacks.gitbrowse.Config
M.opts = {
  notify = true,
  what = 'file',
  -- WSL: Open URLs in Windows browser
  open = os_utils.detect_os() == 'wsl' and function(url)
    vim.fn.jobstart({ 'cmd.exe', '/c', 'start', url:gsub('&', '^&') }, { detach = true })
  end or nil,
}

return M
