-- https://github.com/folke/todo-comments.nvim

return {
  'folke/todo-comments.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  dependencies = { 'nvim-lua/plenary.nvim' },
  opts = {},
  keys = {
    {
      '<leader>xt',
      function()
        Snacks.picker.todo_comments()
      end,
      desc = 'Todo',
    },
    {
      '<leader>xT',
      function()
        Snacks.picker.todo_comments({ keywords = { 'TODO', 'FIX', 'FIXME' } })
      end,
      desc = 'Todo/Fix/Fixme',
    },
    {
      ']t',
      function()
        require('todo-comments').jump_next()
      end,
      desc = 'Next todo comment',
    },
    {
      '[t',
      function()
        require('todo-comments').jump_prev()
      end,
      desc = 'Previous todo comment',
    },
  },
}
