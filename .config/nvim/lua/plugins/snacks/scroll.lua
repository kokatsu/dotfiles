local M = {}

--- @type snacks.scroll.Config
M.opts = {
  animate = {
    duration = { step = 10, total = 200 },
    easing = 'linear',
  },
  animate_repeat = {
    delay = 100,
    duration = { step = 5, total = 50 },
    easing = 'linear',
  },
  filter = function(buf)
    return vim.g.snacks_scroll ~= false and vim.b[buf].snacks_scroll ~= false and vim.bo[buf].buftype ~= 'terminal'
  end,
}

return M
