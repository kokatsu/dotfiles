-- Neovim オプション設定

-- 行末の1文字先までカーソルを移動できる
vim.o.virtualedit = 'onemore'

-- Window分割時のパディング設定
vim.o.fillchars = 'vert:│,fold: ,eob: ' -- 垂直分割線の文字を設定
vim.o.winbar = '%=%m %f' -- ウィンドウバーの表示設定

-- マウスを有効
vim.opt.mouse = 'a'
-- クリップボードを共有
vim.opt.clipboard = 'unnamed,unnamedplus'

-- 行頭行末の左右移動で行をまたぐ
vim.opt.whichwrap = 'b,s,h,l,<,>,[,],~'

-- tabをスペースに変換
vim.opt.expandtab = true

-- https://zenn.dev/vim_jp/articles/511d7982a64967
-- カーソル行をハイライト
vim.opt.cursorline = true
-- ターミナルのカラーを有効にする
vim.opt.termguicolors = true
-- 補完候補の表示
vim.opt.wildoptions = 'pum'
-- フローティングウィンドウの境界線の透明度
vim.opt.pumblend = 30
-- 背景色
vim.opt.background = 'dark'

-- 行番号の表示
vim.opt.number = true
-- 相対行番号の表示
vim.opt.relativenumber = true

-- 検索時に大文字小文字を無視
vim.opt.ignorecase = true
-- 検索時に大文字が含まれている場合、ignorecaseを無効化
vim.opt.smartcase = true

-- スワップファイルを作成しない
vim.opt.swapfile = false
