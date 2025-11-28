-- ハイライト設定

-- SnacksPicker系
vim.api.nvim_set_hl(0, 'SnacksPicker', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'SnacksPickerBorder', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'SnacksPickerInput', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'SnacksPickerInputBorder', { bg = 'NONE' })

-- Window分割の境界線の色を設定
vim.api.nvim_set_hl(0, 'VertSplit', { fg = '#6c7086', bg = 'NONE' })
vim.api.nvim_set_hl(0, 'WinSeparator', { fg = '#6c7086', bg = 'NONE' })

-- 非アクティブWindowの背景色をカスタマイズ
vim.api.nvim_set_hl(0, 'NormalNC', { bg = 'NONE' }) -- 非アクティブWindowの背景色を透明に
vim.api.nvim_set_hl(0, 'LineNr', { fg = '#6c7086', bg = 'NONE' }) -- 行番号の色
vim.api.nvim_set_hl(0, 'LineNrNC', { fg = '#45475a', bg = 'NONE' }) -- 非アクティブWindowの行番号の色
