-- https://github.com/delphinus/md-render.nvim

return {
  'delphinus/md-render.nvim',
  version = '*',
  dependencies = {
    { 'nvim-tree/nvim-web-devicons', version = '*' },
    { 'delphinus/budoux.lua', version = '*' },
  },
  ft = { 'markdown' },
  cmd = { 'MdRender', 'MdRenderTab', 'MdRenderPager', 'MdRenderDemo' },
  config = function()
    vim.api.nvim_create_user_command('MdRender', function()
      require('md-render').preview.show({ max_width = 120 })
    end, { desc = 'Markdown preview in floating window (toggle)' })
  end,
}
