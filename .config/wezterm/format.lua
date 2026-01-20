---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

local colors = require('colors')

local M = {}

local default_color = colors.palette.blue
local zoomed_color = colors.palette.peach

-- プロセス名に応じたアイコンと色の定義
-- https://zenn.dev/gsy0911/articles/a7347e1a2d8d31
local nf = wezterm.nerdfonts --[[@as table]]

local process_icons = {
  ['nvim'] = { icon = nf.linux_neovim, color = colors.palette.green },
  ['vim'] = { icon = nf.dev_vim, color = colors.palette.green },
  ['docker'] = { icon = nf.md_docker, color = colors.palette.blue },
  ['docker-compose'] = { icon = nf.md_docker, color = colors.palette.blue },
  ['python'] = { icon = nf.dev_python, color = colors.palette.yellow },
  ['python3'] = { icon = nf.dev_python, color = colors.palette.yellow },
  ['node'] = { icon = nf.md_nodejs, color = colors.palette.green },
  ['npm'] = { icon = nf.md_npm, color = colors.palette.red },
  ['pnpm'] = { icon = nf.md_npm, color = colors.palette.peach },
  ['deno'] = { icon = nf.seti_typescript, color = colors.palette.yellow },
  ['bun'] = { icon = nf.md_food_croissant, color = colors.palette.peach },
  ['git'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['lazygit'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['gh'] = { icon = nf.dev_github_badge, color = colors.palette.lavender },
  ['cargo'] = { icon = nf.dev_rust, color = colors.palette.peach },
  ['rustc'] = { icon = nf.dev_rust, color = colors.palette.peach },
  ['go'] = { icon = nf.md_language_go, color = colors.palette.sky },
  ['kubectl'] = { icon = nf.md_kubernetes, color = colors.palette.blue },
  ['make'] = { icon = nf.seti_makefile, color = colors.palette.peach },
  ['nix'] = { icon = nf.linux_nixos, color = colors.palette.sky },
  ['ssh'] = { icon = nf.md_ssh, color = colors.palette.mauve },
  ['claude'] = { icon = nf.md_robot_happy, color = colors.palette.peach },
  ['zsh'] = { icon = nf.dev_terminal, color = colors.palette.text },
  ['bash'] = { icon = nf.dev_terminal, color = colors.palette.text },
  ['fish'] = { icon = nf.dev_terminal, color = colors.palette.text },
}

local default_icon = { icon = nf.md_folder_marker, color = colors.palette.text }

--- プロセス名からアイコンと色を取得する
---@param pane any
---@return { icon: string, color: string }
local function get_process_icon(pane)
  -- Claude CLIはNode.jsで動作するため、WEZTERM_PROGで判定
  local wezterm_prog = pane.user_vars and pane.user_vars.WEZTERM_PROG or ''
  if wezterm_prog:find('claude') then
    return process_icons['claude']
  end

  local process_name = pane.foreground_process_name or ''
  -- パスからプロセス名のみを取得
  local name = process_name:match('([^/\\]+)$') or ''

  for pattern, icon_info in pairs(process_icons) do
    if name:find(pattern) then
      return icon_info
    end
  end

  return default_icon
end

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

    -- 現在存在するペインIDを収集
    local active_pane_ids = {}
    for _, tab in ipairs(window:mux_window():tabs()) do
      for _, p in ipairs(tab:panes()) do
        active_pane_ids[p:pane_id()] = true
      end
    end

    -- 存在しないペインのキャッシュをクリーンアップ
    for cached_id in pairs(title_cache) do
      if not active_pane_ids[cached_id] then
        title_cache[cached_id] = nil
      end
    end

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

    -- プロセスに応じたアイコンと色を取得
    local icon_info = get_process_icon(pane)

    -- アクティブ/非アクティブとズーム状態に応じて背景色を変更
    local bg_color
    local fg_color
    local icon_color
    if tab.is_active then
      -- アクティブタブ
      if tab.active_pane.is_zoomed then
        bg_color = zoomed_color -- ズームしているとき
      else
        bg_color = default_color -- ズームしていないとき
      end
      fg_color = colors.palette.crust
      icon_color = colors.palette.crust -- アクティブ時はアイコンも同じ色
    else
      -- 非アクティブタブ（薄い色）
      bg_color = colors.palette.base
      fg_color = colors.palette.text
      icon_color = icon_info.color -- 非アクティブ時はプロセスの色
    end

    return {
      { Background = { Color = bg_color } },
      { Foreground = { Color = icon_color } },
      { Text = ' ' .. icon_info.icon .. ' ' },
      { Foreground = { Color = fg_color } },
      { Text = title .. ' ' },
    }
  end)

  -- ベルを鳴らしたときに通知を出す
  -- 注: macOSではtoast_notificationが動作しないため、
  -- Claude Codeの通知はhooks + terminal-notifierを使用
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
