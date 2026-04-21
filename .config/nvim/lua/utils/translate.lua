-- translate-shell (trans) で英語→日本語翻訳してフロートに表示
local M = {}

local function show_float(lines)
  vim.lsp.util.open_floating_preview(lines, 'markdown', {
    border = 'rounded',
    max_width = 80,
    wrap = true,
    focus = false,
  })
end

local function run_trans(text)
  if not text or text == '' then
    vim.notify('翻訳するテキストがありません', vim.log.levels.WARN)
    return
  end
  vim.system({ 'trans', '-b', '-no-warn', '-t', 'ja' }, { text = true, stdin = text }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        vim.notify('翻訳に失敗しました: ' .. vim.trim(out.stderr or ''), vim.log.levels.ERROR)
        return
      end
      local stdout = vim.trim(out.stdout or '')
      if stdout == '' then
        vim.notify('翻訳結果が空でした', vim.log.levels.WARN)
        return
      end
      show_float(vim.split(stdout, '\n'))
    end)
  end)
end

function M.translate_comment()
  local node = vim.treesitter.get_node()
  if not node or not node:type():match('comment') then
    vim.notify('カーソル位置にコメントがありません', vim.log.levels.WARN)
    return
  end
  run_trans(vim.treesitter.get_node_text(node, 0))
end

function M.translate_visual()
  vim.cmd('normal! "vy')
  run_trans(vim.fn.getreg('v'))
end

return M
