return {
  'catgoose/nvim-colorizer.lua',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    require('colorizer').setup({
      filetypes = {
        'vue',
        'css',
        'scss',
        'html',
        'javascript',
        'typescript',
        'typescriptreact',
        'javascriptreact',
        'lua',
      },
      options = {
        parsers = {
          css = true,
          names = { enable = false },
        },
      },
    })
  end,
}
