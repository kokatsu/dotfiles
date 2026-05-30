-- moonbit.nvim はインデント幅を設定しないため、.editorconfig が無いと
-- Neovim 既定の 8 に落ちる。MoonBit 慣習の 2 スペースを常に保証する。
local tabwidth = 2
vim.opt_local.expandtab = true
vim.opt_local.tabstop = tabwidth
vim.opt_local.softtabstop = tabwidth
vim.opt_local.shiftwidth = tabwidth
