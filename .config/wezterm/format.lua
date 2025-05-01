local wezterm = require('wezterm')

-- https://qiita.com/showchan33/items/c91bb7f6f2b89e9ed57d
-- 現在のディレクトリ名を取得する
local get_cwd_name = function(pane)
  local cwd_uri = pane and pane:get_current_working_dir()
  local cwd_uri_string = wezterm.to_string(cwd_uri)
  local cwd = cwd_uri_string:gsub('^file://', '')

  if not cwd then
    return nil
  end

  local cwd_name = cwd:match('^.*/(.*)$')
  return cwd_name
end

-- 各タブのディレクトリ名を記憶しておくテーブル
local title_cache = {}

-- 各タブ（正確にはpane）にディレクトリ名を記憶させる
wezterm.on('update-status', function(window, pane)
  local title = get_cwd_name(pane)
  local pane_id = pane:pane_id()

  title_cache[pane_id] = title
end)

-- タブのタイトルを変更
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local pane_id = pane.pane_id

  local title = tab.active_pane.title
  if title_cache[pane_id] then
    title = title_cache[pane_id]
  end

  -- nf-md-folder_marker
  return ' 󱉭 ' .. title .. ' '
end)

-- ウィンドウのタイトルを変更
wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local zoomed = ''
  if tab.active_pane.is_zoomed then
    zoomed = '[Z] '
  end

  local index = ''
  if #tabs > 1 then
    index = string.format('[%d/%d] ', tab.tab_index + 1, #tabs)
  end

  local title = tab.active_pane.title

  local pane_id = pane.pane_id

  -- 記憶させていたディレクトリ名を取り出す
  if title_cache[pane_id] then
    title = title_cache[pane_id]
  end

  return zoomed .. index .. title
end)
