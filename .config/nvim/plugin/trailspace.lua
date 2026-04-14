-- Trailing whitespace highlight and auto-trim (replaces mini.trailspace)

local group = vim.api.nvim_create_augroup('Trailspace', { clear = true })

local function set_hl(visible)
  -- catppuccin palette の red を使用 (flavor 追従)
  local ok, palettes = pcall(require, 'catppuccin.palettes')
  local red = ok and palettes.get_palette().red or '#f38ba8'
  vim.api.nvim_set_hl(0, 'Trailspace', { bg = visible and red or 'NONE' })
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

-- Manage trailing whitespace matches per window
local function clear_matches()
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == 'Trailspace' then
      vim.fn.matchdelete(match.id)
    end
  end
end

local function add_match()
  clear_matches()
  if vim.bo.buftype == '' then
    -- \%#\@<! excludes cursor position so insert-mode typing is not highlighted
    vim.fn.matchadd('Trailspace', [[\s\+\%#\@<!$]])
  end
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufEnter', 'FileType' }, {
  group = group,
  callback = function()
    -- Defer so that buftype/filetype are fully set before checking
    vim.schedule(add_match)
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
