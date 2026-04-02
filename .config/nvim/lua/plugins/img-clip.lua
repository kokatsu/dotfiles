-- https://github.com/HakonHarnes/img-clip.nvim

return {
  'HakonHarnes/img-clip.nvim',
  event = 'VeryLazy',
  opts = {},
  keys = {
    { '<leader>p', '<cmd>PasteImage<cr>', desc = 'Paste image from clipboard' },
  },
}
