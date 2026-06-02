-- Terminal設定
local M = {}

M.opts = {
  win = {
    position = 'float',
    border = 'rounded',
    width = 0.8,
    height = 0.8,
    keys = {
      term_normal = false,
      term_double_escape = {
        '<esc><esc>',
        function()
          vim.cmd.stopinsert()
        end,
        mode = 't',
        desc = 'Double escape to normal mode',
      },
    },
  },
}

return M
