local M = {}

--- @type snacks.gitbrowse.Config
M.opts = {
  -- WSL: Open URLs in Windows browser
  open = vim.fn.has('wsl') == 1 and require('utils.windows').open_url or nil,
}

return M
