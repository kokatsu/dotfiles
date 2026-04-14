-- ハイライト設定 (flavor 非依存のもの; flavor 連動は catppuccin.nvim の custom_highlights へ)

-- SnacksPicker系
vim.api.nvim_set_hl(0, 'SnacksPicker', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'SnacksPickerBorder', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'SnacksPickerInput', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'SnacksPickerInputBorder', { bg = 'NONE' })

-- コードブロック内テキストの前景色をクリア（injection ハイライトを優先）
vim.api.nvim_set_hl(0, '@markup.raw.block', { fg = 'NONE' })

-- 非アクティブ Window の背景色を透明に
vim.api.nvim_set_hl(0, 'NormalNC', { bg = 'NONE' })
