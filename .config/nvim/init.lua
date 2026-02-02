-- https://zenn.dev/vim_jp/articles/c96e9b1bdb9241
vim.env.XDG_STATE_HOME = '/tmp'

-- snacks_dashboardでmini.trailspaceを無効化
do
  local function hide_trailspace()
    vim.api.nvim_set_hl(0, 'MiniTrailspace', { bg = 'NONE' })
  end

  local function show_trailspace()
    vim.api.nvim_set_hl(0, 'MiniTrailspace', { bg = '#f38ba8' })
  end

  local function is_dashboard_open()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'snacks_dashboard' then
        return true
      end
    end
    return false
  end

  -- 起動時は透明
  hide_trailspace()

  -- ColorScheme後もダッシュボードが開いていれば透明を維持
  vim.api.nvim_create_autocmd('ColorScheme', {
    callback = function()
      if is_dashboard_open() then
        hide_trailspace()
      end
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'snacks_dashboard',
    callback = function()
      vim.b.minitrailspace_disable = true
      hide_trailspace()
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    callback = function()
      if vim.bo.filetype == 'snacks_dashboard' then
        show_trailspace()
      end
    end,
  })
end

-- Workaround for neovim-nightly lua treesitter query incompatibility
-- The bundled query references 'operator' field that no longer exists in lua grammar
-- Pre-set the highlights query before any lua file is opened
local query_path = vim.fn.stdpath('config') .. '/after/queries/lua/highlights.scm'
local ok, query_content = pcall(vim.fn.readfile, query_path)
if ok and query_content then
  pcall(vim.treesitter.query.set, 'lua', 'highlights', table.concat(query_content, '\n'))
end

require('config.lazy')
require('config.options')
require('config.keymaps')
require('config.autocmds')
require('config.highlights')
