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
    grep = {
      formatters = {
        file = {
          truncate = 'left',
          min_width = 80,
        },
      },
    },
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

-- Grep file type の MRU 履歴 (最後に選んだものが先頭)
local ft_history_file = vim.fs.joinpath(vim.fn.stdpath('state'), 'snacks-grep-ft.json')
local ft_history_max = 50

local function ft_history_read()
  local read_ok, decoded = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(ft_history_file), '\n'))
  end)
  return (read_ok and vim.islist(decoded)) and decoded or {}
end

local function ft_history_push(name)
  local history = { name }
  for _, prev in ipairs(ft_history_read()) do
    if prev ~= name and #history < ft_history_max then
      history[#history + 1] = prev
    end
  end
  vim.fn.mkdir(vim.fs.dirname(ft_history_file), 'p')
  vim.fn.writefile({ vim.json.encode(history) }, ft_history_file)
end

-- 履歴にある型を MRU 順で前に、残りは rg --type-list の順のまま
local function ft_sort_by_mru(types)
  local rank = {}
  for i, name in ipairs(ft_history_read()) do
    rank[name] = i
  end

  local recent, rest = {}, {}
  for _, t in ipairs(types) do
    table.insert(rank[t.name] and recent or rest, t)
  end
  table.sort(recent, function(a, b)
    return rank[a.name] < rank[b.name]
  end)

  return vim.list_extend(recent, rest)
end

-- Grep (filtered by rg file type) action
function M.grep_ft_action()
  local out = vim.system({ 'rg', '--type-list' }, { text = true }):wait()
  if out.code ~= 0 then
    vim.notify('rg --type-list failed', vim.log.levels.ERROR)
    return
  end

  local types = {}
  for line in vim.gsplit(out.stdout, '\n', { trimempty = true }) do
    local name, globs = line:match('^(%S+):%s*(.*)$')
    if name then
      types[#types + 1] = { name = name, globs = globs }
    end
  end

  Snacks.picker.select(ft_sort_by_mru(types), {
    prompt = 'Select file type',
    format_item = function(item)
      return ('%-14s %s'):format(item.name, item.globs)
    end,
  }, function(choice)
    if not choice then
      return
    end
    if not pcall(ft_history_push, choice.name) then
      vim.notify('failed to save grep file type history', vim.log.levels.WARN)
    end
    Snacks.picker.grep({
      cmd = 'rg',
      ignored = true,
      hidden = true,
      regex = true,
      ft = choice.name,
      exclude = common_exclude,
    })
  end)
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
