-- Toggle markdown checkbox: - [ ] <-> - [x]
local function toggle_checkbox()
  local line = vim.api.nvim_get_current_line()
  if line:match('%- %[x%]') then
    line = line:gsub('%- %[x%]', '- [ ]', 1)
  elseif line:match('%- %[ %]') then
    line = line:gsub('%- %[ %]', '- [x]', 1)
  else
    return
  end
  vim.api.nvim_set_current_line(line)
end

vim.keymap.set('n', '<leader>tx', toggle_checkbox, { buffer = true, desc = 'Toggle checkbox' })

-- kakehashi が Tree-sitter ハイライトを止めると highlights.scm の conceal も効かなくなるため、
-- インラインコードの ` は extmark で隠す
local ns = vim.api.nvim_create_namespace('markdown_code_span_conceal')
local query = vim.treesitter.query.parse('markdown_inline', '(code_span_delimiter) @delimiter')

local function conceal_code_span_delimiters(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local parser = vim.treesitter.get_parser(bufnr, 'markdown', { error = false })
  if not parser then
    return
  end
  parser:parse(true)
  parser:for_each_tree(function(tree, ltree)
    if ltree:lang() ~= 'markdown_inline' then
      return
    end
    for _, node in query:iter_captures(tree:root(), bufnr) do
      local sr, sc, er, ec = node:range()
      if ec - sc < 3 then
        vim.api.nvim_buf_set_extmark(bufnr, ns, sr, sc, {
          end_row = er,
          end_col = ec,
          conceal = '',
          -- FileType 時点で構文木がバッファより古く、範囲外になることがある
          strict = false,
        })
      end
    end
  end)
end

local bufnr = vim.api.nvim_get_current_buf()
vim.opt_local.conceallevel = 2
conceal_code_span_delimiters(bufnr)
local group = vim.api.nvim_create_augroup('markdown_code_span_conceal', { clear = false })
vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
  group = group,
  buffer = bufnr,
  callback = function()
    conceal_code_span_delimiters(bufnr)
  end,
})
