return {
  'norcalli/nvim-colorizer.lua',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    require('colorizer').setup({
      'vue',
      'css',
      'scss',
      'html',
      'javascript',
      'typescript',
      'typescriptreact',
      'javascriptreact',
      'lua',
    }, {
      RGB = true,
      RRGGBB = true,
      names = false,
      RRGGBBAA = true,
      css = true,
      css_fn = true,
    })
  end,
}
