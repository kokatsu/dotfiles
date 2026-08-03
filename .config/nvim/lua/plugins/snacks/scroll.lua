local M = {}

--- @type snacks.scroll.Config
M.opts = {
  -- スクロールの度に total=200ms のアニメーションを待つことになり、
  -- 体感の遅延として積み上がるため無効化。
  -- 以下の animate / animate_repeat は再度有効にするときのために残す。
  enabled = false,
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
