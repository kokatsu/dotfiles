-- Explorer設定
local M = {}

-- 共通の exclude 設定
local ok, common_exclude = pcall(require, 'plugins.snacks.exclude')
if not ok then
  common_exclude = {}
end

-- Explorer共通設定
local side_preview_min_columns = 140

local function side_preview_layout()
  return {
    cycle = true,
    layout = {
      box = 'horizontal',
      width = 0.85,
      height = 0.85,
      {
        box = 'vertical',
        border = 'rounded',
        title = '{source} {live} {flags}',
        title_pos = 'center',
        {
          win = 'input',
          height = 1,
          border = 'bottom',
        },
        {
          win = 'list',
          border = 'none',
        },
      },
      {
        win = 'preview',
        border = 'rounded',
        width = 0.7,
        title = '{preview}',
      },
    },
  }
end

local function bottom_preview_layout()
  return {
    cycle = true,
    layout = {
      box = 'vertical',
      width = 0.85,
      height = 0.85,
      {
        box = 'vertical',
        border = 'rounded',
        title = '{source} {live} {flags}',
        title_pos = 'center',
        {
          win = 'input',
          height = 1,
          border = 'bottom',
        },
        {
          win = 'list',
          border = 'none',
        },
      },
      {
        win = 'preview',
        border = 'rounded',
        height = 0.4,
        title = '{preview}',
      },
    },
  }
end

local function explorer_layout()
  if vim.o.columns >= side_preview_min_columns then
    return side_preview_layout()
  end

  return bottom_preview_layout()
end

M.config = {
  auto_close = true,
  hidden = true,
  ignored = true,
  exclude = common_exclude,
  layout = explorer_layout,
}

-- Explorer opts
M.opts = {
  enabled = true,
}

-- Explorer action
function M.action()
  Snacks.picker.explorer(M.config)
end

return M
