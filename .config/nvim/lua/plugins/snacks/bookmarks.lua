-- Bookmarks picker: プロジェクトルートの .bookmarks ファイルから読み込む
local M = {}

local BOOKMARKS_FILE = '.bookmarks'

--- プロジェクトルートを取得
---@return string
local function get_root()
  return vim.fs.root(0, '.git') or vim.uv.cwd()
end

--- .bookmarks ファイルからエントリを読み込む
---@param root string
---@return snacks.picker.finder.Item[]
local function load_bookmarks(root)
  local path = root .. '/' .. BOOKMARKS_FILE
  local f = io.open(path, 'r')
  if not f then
    return {}
  end

  local items = {}
  for line in f:lines() do
    line = vim.trim(line)
    if line ~= '' and not line:match('^#') then
      table.insert(items, {
        file = root .. '/' .. line,
        text = line,
      })
    end
  end
  f:close()
  return items
end

function M.action()
  local root = get_root()
  local items = load_bookmarks(root)

  if #items == 0 then
    vim.notify(BOOKMARKS_FILE .. ' not found or empty (root: ' .. root .. ')', vim.log.levels.WARN)
    return
  end

  Snacks.picker({
    title = 'Bookmarks',
    items = items,
  })
end

return M
