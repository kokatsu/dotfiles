-- https://github.com/toppair/peek.nvim

return {
  'toppair/peek.nvim',
  event = { 'VeryLazy' },
  build = 'deno task --quiet build:fast',
  config = function()
    local app = 'browser'
    if vim.fn.has('wsl') == 1 then
      app = { 'wslview' }
    end
    require('peek').setup({
      app = app,
    })
    vim.api.nvim_create_user_command('PeekOpen', require('peek').open, {})
    vim.api.nvim_create_user_command('PeekClose', require('peek').close, {})
  end,
}
