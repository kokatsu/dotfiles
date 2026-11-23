local is_wsl = vim.fn.has('wsl') == 1

-- 行末の1文字先までカーソルを移動できる
vim.o.virtualedit = 'onemore'

vim.o.fillchars = 'vert:│,fold: ,eob: '
vim.o.winbar = '%=%m %f'

vim.opt.mouse = 'a'
-- クリップボードはyank時のみ同期（autocmds.luaで制御）
vim.opt.clipboard = ''

-- WSL2環境ではxselを使用。WSLgがXクリップボードとWindowsクリップボードを
-- 双方向同期するため、win32yank.exeを経由しなくてもWindows側と共有できる。
-- win32yank.exeはWindowsプロセスの起動コスト(実測462ms)がyank/paste毎にかかり、
-- xsel(実測6ms)との差がそのまま体感のもたつきになる。
-- wl-copyはprimary selectionの扱いに問題があるため使わない。
if is_wsl and vim.fn.executable('xsel') == 1 then
  vim.g.clipboard = {
    name = 'xsel-wslg',
    copy = {
      ['+'] = 'xsel -ib',
      ['*'] = 'xsel -ib',
    },
    paste = {
      ['+'] = 'xsel -ob',
      ['*'] = 'xsel -ob',
    },
    cache_enabled = 0,
  }
end

if is_wsl then
  vim.keymap.set('n', 'gx', function()
    require('utils.windows').open_url(vim.fn.expand('<cfile>'))
  end, { desc = 'Open URL in Windows browser' })
  if vim.fn.executable('wslview') == 1 then
    vim.keymap.set('n', 'gX', function()
      vim.fn.jobstart({ 'wslview', vim.fn.expand('%:p') }, { detach = true })
    end, { desc = 'Open current file in Windows browser' })
  end
end

-- 行頭行末の左右移動で行をまたぐ
vim.opt.whichwrap = 'b,s,h,l,<,>,[,],~'

vim.opt.expandtab = true

-- https://zenn.dev/vim_jp/articles/511d7982a64967
vim.opt.cursorline = true
vim.opt.pumblend = 30
-- 背景色 (APPEARANCE 環境変数で dark/light を切替; シェルが OS 設定から検出)
vim.opt.background = vim.env.APPEARANCE == 'light' and 'light' or 'dark'

vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.swapfile = false

vim.opt.undofile = true

-- 診断サインでレイアウトシフト防止
vim.opt.signcolumn = 'yes'

vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- CursorHold等のイベント発火までの待機時間（デフォルト4000ms）
-- 外部ツールによるファイル変更の検知を速くするため短く設定
vim.opt.updatetime = 300

-- Treesitter非同期パースのタイムアウト（デフォルト2000ms）
-- Markdownなどインジェクションが多いファイルでハイライトが途切れるのを防ぐ
-- 大きすぎるとUI全体がブロックされるため控えめに設定
vim.o.redrawtime = 3000

-- プロジェクトローカルの .nvim.lua / .nvimrc / .exrc を読み込む
-- Neovim 0.9+ の trust モデルにより未承認ファイルは実行されない（:trust で承認）
-- 0.12+ は親ディレクトリも探すため、~/workspace/.nvim.lua は配下の全リポジトリに効く
vim.o.exrc = true
