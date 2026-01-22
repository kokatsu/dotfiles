-- Picker設定
local M = {}

-- 共通の exclude 設定
local ok, common_exclude = pcall(require, 'plugins.snacks.exclude')
if not ok then
  common_exclude = {}
end

local explorer = require('plugins.snacks.explorer')

-- Picker opts
M.opts = {
  enabled = true,
  -- ESCキーで即座に閉じる設定
  win = {
    input = {
      keys = {
        -- ESCキーを押したら即座に閉じる
        ['<esc>'] = { 'close', mode = { 'i', 'n' } },
      },
      wo = {
        winblend = 100,
      },
    },
    list = {
      wo = {
        relativenumber = true,
        winblend = 100,
      },
    },
    preview = {
      wo = {
        winblend = 100,
      },
    },
  },
  -- https://www.reddit.com/r/neovim/comments/1kbqsdc/snacks_explorer_preview_to_the_right/
  sources = {
    explorer = explorer.config,
  },
}

-- Matcher opts
M.matcher_opts = {
  fuzzy = true,
  smart_case = true,
  ignorecase = true,
  sort_empty = false,
  filename_bonus = true,
  file_pos = true,
  cwd_bonus = true,
  frecency = true,
  history_bonus = true,
}

-- Smart find action
function M.smart_action()
  Snacks.picker.smart({
    hidden = true,
    ignored = true,
    exclude = common_exclude,
  })
end

-- Grep action
function M.grep_action()
  Snacks.picker.grep({
    cmd = 'rg',
    ignored = true,
    hidden = true,
    regex = true,
    exclude = common_exclude,
  })
end

-- Grep (no regex) action
function M.grep_no_regex_action()
  Snacks.picker.grep({
    cmd = 'rg',
    hidden = true,
    regex = false,
  })
end

return M
