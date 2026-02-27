-- Terminal設定
local M = {}

M.opts = {
  win = {
    position = 'bottom',
  },
  keys = {
    term_normal = {
      '<esc>',
      function(self)
        self.esc_timer = self.esc_timer or vim.uv.new_timer()
        if self.esc_timer:is_active() then
          self.esc_timer:stop()
          vim.cmd('stopinsert')
        else
          self.esc_timer:start(500, 0, function() end)
          return '<esc>'
        end
      end,
      mode = 't',
      expr = true,
      desc = 'Double escape to normal mode',
    },
  },
}

return M
