-- https://github.com/kokatsu/peek.nvim

return {
  name = 'peek.nvim',
  dir = vim.fn.stdpath('data') .. '/nix-plugins/peek.nvim',
  -- コマンド経由でしか使わないので、lazy.nvim のスタブコマンドで初回呼び出し時に読み込む
  cmd = { 'PeekOpen', 'PeekClose' },
  config = function()
    local app = 'browser'
    if vim.fn.has('wsl') == 1 and vim.fn.executable('wslview') == 1 then
      app = { 'wslview' }
    end
    require('peek').setup({
      app = app,
    })
    vim.api.nvim_create_user_command('PeekOpen', require('peek').open, {})
    vim.api.nvim_create_user_command('PeekClose', require('peek').close, {})
  end,
}
