-- Trailing whitespace highlight and auto-trim (replaces mini.trailspace)

local group = vim.api.nvim_create_augroup('Trailspace', { clear = true })

local function set_hl(visible)
  vim.api.nvim_set_hl(0, 'Trailspace', { bg = visible and '#f38ba8' or 'NONE' })
end

-- Start hidden (dashboard may be showing at startup)
set_hl(false)

-- Dashboard integration: hide highlight while snacks_dashboard is open
local function is_dashboard_open()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'snacks_dashboard' then
      return true
    end
  end
  return false
end

vim.api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    set_hl(not is_dashboard_open())
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'snacks_dashboard',
  callback = function()
    set_hl(false)
  end,
})

vim.api.nvim_create_autocmd('BufLeave', {
  group = group,
  callback = function()
    if vim.bo.filetype == 'snacks_dashboard' then
      set_hl(true)
    end
  end,
})

-- Add trailing whitespace match to windows with normal buffers
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'FileType' }, {
  group = group,
  callback = function()
    for _, match in ipairs(vim.fn.getmatches()) do
      if match.group == 'Trailspace' then
        vim.fn.matchdelete(match.id)
      end
    end
    if vim.bo.buftype == '' then
      vim.fn.matchadd('Trailspace', [[\s\+$]])
    end
  end,
})

-- Trim trailing whitespace on save
vim.api.nvim_create_autocmd('BufWritePre', {
  group = group,
  callback = function()
    local exclude_ft = { 'diff', 'gitcommit', 'markdown' }
    if vim.bo.buftype ~= '' or vim.tbl_contains(exclude_ft, vim.bo.filetype) then
      return
    end
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    pcall(vim.api.nvim_win_set_cursor, 0, pos)
  end,
})
