-- Detect Deno scripts by shebang and set buffer variable for LSP

local function check_deno_shebang(bufnr)
  local shebang = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if not shebang or shebang:sub(1, 2) ~= '#!' then
    return false
  end

  shebang = shebang:gsub('%s+', ' ')

  -- Check for deno in shebang
  if vim.startswith(shebang, '#!/usr/bin/env deno') or vim.startswith(shebang, '#!/usr/bin/env -S deno') then
    return true
  end

  -- Check direct path to deno
  local idx_space = shebang:find(' ')
  local path = string.sub(shebang, 3, idx_space and idx_space - 1 or nil)
  local cmd = vim.fs.basename(path)
  if cmd == 'deno' then
    return true
  end

  return false
end

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  pattern = '*',
  callback = function(args)
    if check_deno_shebang(args.buf) then
      vim.b[args.buf].is_deno = true
      vim.bo[args.buf].filetype = 'typescript'
      -- Start denols manually for this buffer
      vim.lsp.start({
        name = 'denols',
        cmd = { 'deno', 'lsp' },
        root_dir = vim.fn.fnamemodify(args.file, ':h'),
      })
    end
  end,
})
