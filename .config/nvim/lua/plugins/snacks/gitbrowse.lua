local M = {}

--- @type snacks.gitbrowse.Config
M.opts = {
  open = vim.fn.has('wsl') == 1 and require('utils.windows').open_url or nil,
}

return M
