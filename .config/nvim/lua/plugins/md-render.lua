-- https://github.com/delphinus/md-render.nvim

return {
  'delphinus/md-render.nvim',
  version = '*',
  dependencies = {
    -- 依存の version は lazy が同名の他のスペックにもマージするので付けない。
    'nvim-tree/nvim-web-devicons',
    { 'delphinus/budoux.lua', version = '*' },
  },
  ft = { 'markdown' },
  cmd = { 'MdRender', 'MdRenderWide' },
  config = function()
    -- プラグインの :MdRender (サブコマンド付き) は幅を指定できないので、別名で足す。
    vim.api.nvim_create_user_command('MdRenderWide', function()
      require('md-render').preview.show({ max_width = 120 })
    end, { desc = 'Markdown preview in floating window, 120 columns (toggle)' })
  end,
}
