-- https://github.com/nvim-lualine/lualine.nvim

return {
  'nvim-lualine/lualine.nvim',
  event = 'VeryLazy',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {
    options = {
      theme = 'auto',
      component_separators = { left = '|', right = '|' },
      section_separators = { left = '', right = '' },
    },
    sections = {
      lualine_a = { 'mode' },
      lualine_b = { 'branch', 'diff', 'diagnostics' },
      lualine_c = { 'filename' },
      lualine_x = {
        function()
          local qf = vim.fn.getqflist({ idx = 0, size = 0 })
          return qf.size > 0 and ('%d/%d'):format(qf.idx, qf.size) or ''
        end,
        'encoding',
        'fileformat',
        'filetype',
      },
      lualine_y = { 'progress' },
      lualine_z = { 'location' },
    },
  },
}
