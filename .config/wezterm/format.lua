local wezterm = require('wezterm') --[[@as Wezterm]]

local colors = require('colors')

local M = {}

local default_color = colors.palette.blue
local zoomed_color = colors.palette.peach

-- https://qiita.com/showchan33/items/c91bb7f6f2b89e9ed57d
-- 現在のディレクトリ名を取得する
local function get_cwd_name(pane)
  local cwd_uri = pane and pane:get_current_working_dir()
  if not cwd_uri then
    return nil
  end

  ---@diagnostic disable-next-line: undefined-field
  local cwd_uri_string = wezterm.to_string(cwd_uri)
  if not cwd_uri_string then
    return nil
  end

  local cwd = cwd_uri_string:gsub('^file://', '')

  if not cwd then
    return nil
  end

  -- Remove trailing slash if present
  cwd = cwd:gsub('/$', '')

  local cwd_name = cwd:match('^.*/(.*)$')

  -- If regex didn't match, try alternative approach
  if not cwd_name then
    cwd_name = cwd:match('([^/]+)$')
  end

  return cwd_name
end

-- ベルを鳴らしたときに通知を出す
-- https://zenn.dev/choplin/articles/cb16c2da711de8
-- https://github.com/ucpr/dotfiles/blob/8dbb7b426f2bf5f820e28aaeabf95b7917537021/wezterm/wezterm.lua
local function get_tab_id(window, pane)
  local mux_window = window:mux_window()
  for i, tab_info in ipairs(mux_window:tabs_with_info()) do
    for _, p in ipairs(tab_info.tab:panes()) do
      if p:pane_id() == pane:pane_id() then
        return i
      end
    end
  end
end

local function is_claude(pane)
  local process_name = pane:get_foreground_process_name()
  if not process_name then
    return false
  end

  if process_name:find('claude') then
    return true
  elseif process_name:find('wslhost.exe') then
    local wezterm_prog = pane:get_user_vars().WEZTERM_PROG
    if wezterm_prog and wezterm_prog:find('claude') then
      return true
    end
  end

  return false
end

-- 各タブのディレクトリ名を記憶しておくテーブル
local title_cache = {}

--- イベントハンドラを登録する
M.apply = function()
  -- 各タブ（正確にはpane）にディレクトリ名を記憶させる
  wezterm.on('update-status', function(window, pane)
    local title = get_cwd_name(pane)
    local pane_id = pane:pane_id()

    title_cache[pane_id] = title

    local border_color = default_color
    local is_zoomed = false
    for _, p in ipairs(window:active_tab():panes_with_info()) do
      if p.is_active and p.is_zoomed then
        is_zoomed = true
        break
      end
    end

    if is_zoomed then
      border_color = zoomed_color
    end

    local window_frame = {
      border_left_width = '0.5cell',
      border_right_width = '0.5cell',
      border_bottom_height = '0.25cell',
      border_top_height = '0.25cell',
      border_left_color = border_color,
      border_right_color = border_color,
      border_bottom_color = border_color,
      border_top_color = border_color,
    }

    local overrides = window:get_config_overrides() or {}
    overrides.window_frame = window_frame
    window:set_config_overrides(overrides)

    window:set_left_status(wezterm.format({}))
    window:set_right_status(wezterm.format({}))
  end)

  -- タブのタイトルを変更
  wezterm.on('format-tab-title', function(tab, _, _, _, _, _)
    local pane = tab.active_pane
    local pane_id = pane.pane_id

    local title = tab.active_pane.title
    if title_cache[pane_id] then
      title = title_cache[pane_id]
    end

    -- タイトルの14文字以降を省略
    if #title > 13 then
      title = title:sub(1, 13) .. '…'
    end

    -- アクティブ/非アクティブとズーム状態に応じて背景色を変更
    local bg_color
    local fg_color
    if tab.is_active then
      -- アクティブタブ
      if tab.active_pane.is_zoomed then
        bg_color = zoomed_color -- ズームしているとき
      else
        bg_color = default_color -- ズームしていないとき
      end
      fg_color = colors.palette.crust
    else
      -- 非アクティブタブ（薄い色）
      bg_color = colors.palette.base
      fg_color = colors.palette.text
    end

    return {
      { Background = { Color = bg_color } },
      { Foreground = { Color = fg_color } },
      -- nf-md-folder_marker
      { Text = ' 󱉭 ' .. title .. ' ' },
    }
  end)

  -- ベルを鳴らしたときに通知を出す
  wezterm.on('bell', function(window, pane)
    if not is_claude(pane) then
      return
    end

    local tab_id = get_tab_id(window, pane)
    local tab_title = get_cwd_name(pane) or 'Unknown Tab'

    window:toast_notification(
      'Claude Code',
      'Task completed (tab_id: ' .. tostring(tab_id) .. ', tab_title: ' .. tab_title .. ')',
      nil,
      4000
    )
  end)
end

return M
