-- Claude Code プロンプト編集用設定

-- @キーでファイルパス補完
vim.keymap.set('i', '@', function()
  local ok, snacks = pcall(require, 'snacks')
  if not ok then
    -- snacks がない場合は通常の@を入力
    vim.api.nvim_feedkeys('@', 'n', true)
    return
  end

  snacks.picker.files({
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.api.nvim_put({ '@' .. item.file .. ' ' }, 'c', true, true)
      end
    end,
  })
end, { buffer = true, desc = 'Insert file path with @' })

-- 保存して終了を簡単に
vim.keymap.set('n', '<leader>q', '<cmd>wq<cr>', { buffer = true, desc = 'Save and quit' })
