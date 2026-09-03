---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

local colors = require('colors')
local platform = require('platform')

local M = {}

local default_color = colors.palette.blue
local zoomed_color = colors.palette.peach

-- プロセス名に応じたアイコンと色の定義
-- https://zenn.dev/gsy0911/articles/a7347e1a2d8d31
local nf = wezterm.nerdfonts --[[@as table]]

local process_icons = {
  -- Editors
  ['nvim'] = { icon = nf.linux_neovim, color = colors.palette.green },
  ['vim'] = { icon = nf.dev_vim, color = colors.palette.green },
  ['vi'] = { icon = nf.linux_neovim, color = colors.palette.green },
  -- Containers
  ['docker'] = { icon = nf.md_docker, color = colors.palette.blue },
  ['docker-compose'] = { icon = nf.md_docker, color = colors.palette.blue },
  ['lazydocker'] = { icon = nf.md_docker, color = colors.palette.blue },
  ['lzd'] = { icon = nf.md_docker, color = colors.palette.blue },
  ['kubectl'] = { icon = nf.md_kubernetes, color = colors.palette.blue },
  -- Languages & Runtimes
  ['python'] = { icon = nf.dev_python, color = colors.palette.yellow },
  ['python3'] = { icon = nf.dev_python, color = colors.palette.yellow },
  ['node'] = { icon = nf.md_nodejs, color = colors.palette.green },
  ['npm'] = { icon = nf.md_npm, color = colors.palette.red },
  ['pnpm'] = { icon = nf.md_npm, color = colors.palette.peach },
  ['deno'] = { icon = nf.seti_typescript, color = colors.palette.yellow },
  ['bun'] = { icon = nf.md_food_croissant, color = colors.palette.peach },
  ['cargo'] = { icon = nf.dev_rust, color = colors.palette.peach },
  ['rustc'] = { icon = nf.dev_rust, color = colors.palette.peach },
  ['go'] = { icon = nf.md_language_go, color = colors.palette.sky },
  -- Git
  ['git'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['lazygit'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['lg'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['git-graph'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['gg'] = { icon = nf.dev_git, color = colors.palette.peach },
  ['gh'] = { icon = nf.dev_github_badge, color = colors.palette.lavender },
  -- CLI Tools
  ['bat'] = { icon = nf.md_file_document, color = colors.palette.yellow },
  ['bag'] = { icon = nf.md_file_document, color = colors.palette.yellow },
  ['eza'] = { icon = nf.md_folder, color = colors.palette.blue },
  ['fd'] = { icon = nf.md_file_search, color = colors.palette.mauve },
  -- Build & System
  ['make'] = { icon = nf.seti_makefile, color = colors.palette.peach },
  ['nix'] = { icon = nf.linux_nixos, color = colors.palette.sky },
  ['ssh'] = { icon = nf.md_ssh, color = colors.palette.mauve },
  -- AI
  ['claude'] = { icon = nf.md_robot_happy, color = colors.palette.peach },
  -- Shells
  ['zsh'] = { icon = nf.dev_terminal, color = colors.palette.text },
  ['bash'] = { icon = nf.dev_terminal, color = colors.palette.text },
  ['fish'] = { icon = nf.dev_terminal, color = colors.palette.text },
}

local default_icon = { icon = nf.md_folder_marker, color = colors.palette.text }

-- feed-watch: GitHub フィード未読表示
local feed_status_cache = nil
local feed_status_last_check = 0
local FEED_STATUS_CHECK_INTERVAL = 30 -- seconds

local function read_feed_status()
  local now = os.time()
  if feed_status_cache ~= nil and (now - feed_status_last_check) < FEED_STATUS_CHECK_INTERVAL then
    return feed_status_cache
  end
  feed_status_last_check = now

  local userprofile = os.getenv('USERPROFILE')
  if not userprofile then
    feed_status_cache = false
    return false
  end

  local path = userprofile .. '\\.cache\\feed-watch\\status.json'
  local file = io.open(path, 'r')
  if not file then
    feed_status_cache = false
    return false
  end

  local content = file:read('*a')
  file:close()

  local ok, data = pcall(wezterm.json_parse, content)
  if not ok or not data or not data.feeds then
    feed_status_cache = false
    return false
  end

  feed_status_cache = data
  return data
end

local function format_feed_status()
  local data = read_feed_status()
  if not data or not data.feeds then
    return {}
  end

  local elements = {}
  -- ソートされた順序で表示
  local names = {}
  for name, _ in pairs(data.feeds) do
    table.insert(names, name)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local info = data.feeds[name]
    if info.unread_count and info.unread_count > 0 then
      if #elements > 0 then
        table.insert(elements, { Text = '  ' })
      end
      local icon = info.type == 'github' and nf.dev_github_badge or nf.md_rss
      table.insert(elements, { Foreground = { Color = colors.palette.overlay1 } })
      table.insert(elements, { Text = icon .. ' ' })
      table.insert(elements, { Foreground = { Color = colors.palette.text } })
      table.insert(elements, { Text = name .. ' (' .. tostring(info.unread_count) .. ') ' })
    end
  end

  return elements
end

local function format_feed_last_updated()
  local data = read_feed_status()
  if not data or not data.last_updated then
    return {}
  end

  return {
    { Foreground = { Color = colors.palette.overlay1 } },
    { Text = nf.md_clock_outline .. ' ' .. os.date('%H:%M', data.last_updated) .. ' ' },
  }
end

-- disk-watch: WSL / Windows のディスク容量警告
local disk_status_cache = nil
local disk_status_last_check = 0
local DISK_STATUS_CHECK_INTERVAL = 30 -- seconds

local function read_disk_status()
  local now = os.time()
  if disk_status_cache ~= nil and (now - disk_status_last_check) < DISK_STATUS_CHECK_INTERVAL then
    return disk_status_cache
  end
  disk_status_last_check = now

  local userprofile = os.getenv('USERPROFILE')
  if not userprofile then
    disk_status_cache = false
    return false
  end

  local path = userprofile .. '\\.cache\\disk-watch\\status.json'
  local file = io.open(path, 'r')
  if not file then
    disk_status_cache = false
    return false
  end

  local content = file:read('*a')
  file:close()

  local ok, data = pcall(wezterm.json_parse, content)
  if not ok or not data or not data.filesystems then
    disk_status_cache = false
    return false
  end

  disk_status_cache = data
  return data
end

local function format_disk_status()
  local data = read_disk_status()
  if not data or not data.filesystems then
    return {}
  end

  local elements = {}
  for _, name in ipairs({ 'windows', 'wsl' }) do
    local info = data.filesystems[name]
    if info and info.level and info.level ~= 'ok' then
      if #elements > 0 then
        table.insert(elements, { Text = '  ' })
      end
      local color = info.level == 'critical' and colors.palette.red or colors.palette.yellow
      table.insert(elements, { Foreground = { Color = color } })
      table.insert(elements, { Text = '󰋊 ' })
      table.insert(elements, { Foreground = { Color = colors.palette.text } })
      table.insert(elements, {
        Text = info.label .. ' ' .. tostring(info.used_percent) .. '% / ' .. tostring(info.available_gib) .. 'G free ',
      })
    end
  end

  return elements
end

-- status-watch: Claude / OpenAI の障害情報
local service_status_cache = {}
local SERVICE_STATUS_CHECK_INTERVAL = 30 -- seconds
-- status-watch は 5 分ごとに更新する。3 周期分を過ぎたデータは取得が止まって
-- いるとみなして描画しない (復旧済みの障害が残り続けるのを防ぐ)
local SERVICE_STATUS_TTL = 900 -- seconds

local function read_service_status(filename)
  local now = os.time()
  local cached = service_status_cache[filename]
  if cached and (now - cached.last_check) < SERVICE_STATUS_CHECK_INTERVAL then
    return cached.data
  end

  local userprofile = os.getenv('USERPROFILE')
  if not userprofile then
    service_status_cache[filename] = { data = false, last_check = now }
    return false
  end

  local path = userprofile .. '\\.cache\\status-watch\\' .. filename
  local file = io.open(path, 'r')
  if not file then
    service_status_cache[filename] = { data = false, last_check = now }
    return false
  end

  local content = file:read('*a')
  file:close()

  local ok, data = pcall(wezterm.json_parse, content)
  if not ok or not data or not data.indicator then
    service_status_cache[filename] = { data = false, last_check = now }
    return false
  end

  service_status_cache[filename] = { data = data, last_check = now }
  return data
end

-- Nerd Fonts の cod-claude (U+EC82) / cod-openai (U+EC81) / cod-github (U+EA84)。
-- wezterm.nerdfonts のテーブルは WezTerm のバージョンに依存するので、コード
-- ポイントを直接指定する。Claude と OpenAI のグリフは WezTerm の fallback に並ぶ
-- 4 フォントのうち PlemolJP35 Console NF にしかない (cod-github は先頭の
-- UDEV Gothic にもある)
local claude_icon = utf8.char(0xec82)
local openai_icon = utf8.char(0xec81)
local github_icon = utf8.char(0xea84)

-- indicator は none / minor / major / critical の 4 値しかない。メンテナンスは
-- indicator ではなく component の under_maintenance として現れる
local service_status_colors = {
  none = colors.palette.green,
  minor = colors.palette.yellow,
  major = colors.palette.peach,
  critical = colors.palette.red,
}

local service_component_colors = {
  degraded_performance = colors.palette.yellow,
  partial_outage = colors.palette.peach,
  major_outage = colors.palette.red,
  under_maintenance = colors.palette.sky,
}

local service_impact_colors = {
  none = colors.palette.yellow,
  minor = colors.palette.yellow,
  major = colors.palette.peach,
  critical = colors.palette.red,
}

-- Statuspage の配列順は severity 順ではないので、代表要素は rank で選ぶ
local service_impact_rank = {
  none = 1,
  minor = 2,
  major = 3,
  critical = 4,
}

local service_component_rank = {
  under_maintenance = 1,
  degraded_performance = 2,
  partial_outage = 3,
  major_outage = 4,
}

--- rank が最大の要素を返す (同率なら先に現れたもの)
---@param items table[]
---@param key string
---@param ranks table<string, integer>
---@return table
local function most_severe(items, key, ranks)
  local worst = items[1]
  local worst_rank = ranks[worst[key]] or 0
  for i = 2, #items do
    local rank = ranks[items[i][key]] or 0
    if rank > worst_rank then
      worst = items[i]
      worst_rank = rank
    end
  end
  return worst
end

--- サービス状態をアイコン 1 つの色で表す。正常でも出し続けるので、
--- 監視が止まっている状態を正常と取り違えないよう、TTL 超過だけは灰色にする
local function format_service_status(filename, icon)
  -- status-watch は WSL 限定なので、Windows 版 WezTerm 以外ではキャッシュが
  -- 存在せず、常に「監視停止」の灰色になってしまう。そこでは何も出さない
  if not platform.is_windows then
    return {}
  end

  local data = read_service_status(filename)
  local color

  if not data or not data.last_updated or os.time() - data.last_updated > SERVICE_STATUS_TTL then
    color = colors.palette.overlay1
  else
    local components = data.components or {}
    local incidents = data.incidents or {}
    local indicator = data.indicator or 'none'

    if indicator ~= 'none' then
      color = service_status_colors[indicator]
    elseif #incidents > 0 then
      color = service_impact_colors[most_severe(incidents, 'impact', service_impact_rank).impact]
    elseif #components > 0 then
      color = service_component_colors[most_severe(components, 'status', service_component_rank).status]
    else
      color = service_status_colors.none
    end
  end

  return {
    { Foreground = { Color = color or colors.palette.yellow } },
    { Text = icon .. ' ' },
  }
end

--- WSLを考慮して実際のプロセス名を取得する
--- WSL上のプロセスはwslhost.exeとして見えるため、WEZTERM_PROGユーザー変数を使用
---@param pane any
---@param use_method boolean? メソッド呼び出し（pane:get_*）を使うか、プロパティアクセス（pane.*）を使うか
---@return string
local function get_process_name(pane, use_method)
  local process_name
  local wezterm_prog

  if use_method then
    process_name = pane:get_foreground_process_name() or ''
    local user_vars = pane:get_user_vars()
    wezterm_prog = user_vars and user_vars.WEZTERM_PROG or ''
  else
    process_name = pane.foreground_process_name or ''
    wezterm_prog = pane.user_vars and pane.user_vars.WEZTERM_PROG or ''
  end

  -- WSL上のプロセスはwslhost.exeとして見える
  -- WEZTERM_PROGが設定されていればそれを使用
  if process_name:find('wslhost.exe') and wezterm_prog ~= '' then
    -- WEZTERM_PROGからコマンド名のみを取得（引数を除去）
    return wezterm_prog:match('^(%S+)') or wezterm_prog
  end

  -- パスからプロセス名のみを取得（.exeも除去）
  local name = process_name:match('([^/\\]+)$') or ''
  return name:gsub('%.exe$', '')
end

--- 指定したパターンにマッチするプロセスかどうかを判定する
---@param pane any
---@param pattern string
---@param use_method boolean? メソッド呼び出しを使うか
---@return boolean
local function is_process(pane, pattern, use_method)
  local name = get_process_name(pane, use_method)
  return name:find(pattern) ~= nil
end

--- プロセス名からアイコンと色を取得する
---@param pane any
---@return { icon: string, color: string }
local function get_process_icon(pane)
  local name = get_process_name(pane, false)

  -- 完全一致で照合する（部分一致だと cargo が go にマッチする等の誤判定が起きる）
  local icon_info = process_icons[name]
  if icon_info then
    return icon_info
  end

  return default_icon
end

-- https://qiita.com/showchan33/items/c91bb7f6f2b89e9ed57d
-- 現在のディレクトリ名を取得する
-- フォルダ名 (cwd) タイトルは herdr のサイドバーが担うため無効化。
-- herdr をやめる場合はコメント解除
--[=[
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
--]=]

local function is_claude(pane)
  return is_process(pane, 'claude', true)
end

--- pane が属するタブの 1-based 位置を返す（見つからなければ nil）
---@param window any
---@param pane any
---@return integer?
local function get_tab_id(window, pane)
  for i, tab_info in ipairs(window:mux_window():tabs_with_info()) do
    for _, p in ipairs(tab_info.tab:panes()) do
      if p:pane_id() == pane:pane_id() then
        return i
      end
    end
  end
end

-- フォルダ名 (cwd) タイトルは herdr のサイドバーが担うため無効化。
-- herdr をやめる場合はコメント解除
--[=[
-- 各タブのディレクトリ名を記憶しておくテーブル
local title_cache = {}
--]=]

--- イベントハンドラを登録する
M.apply = function()
  wezterm.on('update-status', function(window, _pane)
    -- フォルダ名 (cwd) タイトルのキャッシュは herdr のサイドバーが担うため無効化。
    -- herdr をやめる場合はコメント解除し、引数名を _pane → pane に戻す
    --[=[
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
    --]=]

    -- ウィンドウ枠 (window_frame ボーダー) の描画は herdr がペイン枠を持つため無効化。
    -- herdr をやめる場合はコメント解除
    --[=[
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

    -- set_config_overrides は呼ぶたびに config 全体を再評価する高コスト操作のため、
    -- 枠色が実際に変わった時（ズーム状態の変化 / 背景切替で window_frame が消えた時）だけ呼ぶ。
    -- update-status は周期的に発火するので、毎ティック呼ぶと入力遅延の一因になる。
    local overrides = window:get_config_overrides() or {}
    local current_frame = overrides.window_frame
    if not current_frame or current_frame.border_left_color ~= border_color then
      overrides.window_frame = {
        border_left_width = '0.5cell',
        border_right_width = '0.5cell',
        border_bottom_height = '0.25cell',
        border_top_height = '0.25cell',
        border_left_color = border_color,
        border_right_color = border_color,
        border_bottom_color = border_color,
        border_top_color = border_color,
      }
      window:set_config_overrides(overrides)
    end
    --]=]

    window:set_left_status(wezterm.format({}))

    -- ダブルプレス確認メッセージの表示/クリア
    local g = wezterm.GLOBAL or {}
    if g.status_message and g.status_expire then
      if os.time() >= g.status_expire then
        -- タイムアウト: メッセージをクリア
        wezterm.GLOBAL.status_message = nil
        wezterm.GLOBAL.status_expire = nil
        window:set_right_status(wezterm.format({}))
      else
        -- まだ有効: メッセージを再描画（update-statusで上書きされるため）
        window:set_right_status(wezterm.format({
          { Background = { Color = colors.palette.red } },
          { Foreground = { Color = colors.palette.crust } },
          { Text = ' ' .. g.status_message .. ' ' },
        }))
      end
    else
      -- 右ステータスは複数セクションの連結。空のセクションは飛ばす
      local right_elements = {}
      for _, section in ipairs({
        format_feed_status(),
        format_service_status('status.json', claude_icon),
        format_service_status('openai.json', openai_icon),
        format_service_status('github.json', github_icon),
        format_disk_status(),
        format_feed_last_updated(),
      }) do
        if #section > 0 then
          if #right_elements > 0 then
            table.insert(right_elements, { Text = '  ' })
          end
          for _, element in ipairs(section) do
            table.insert(right_elements, element)
          end
        end
      end
      window:set_right_status(wezterm.format(right_elements))
    end
  end)

  -- タブのタイトルを変更
  wezterm.on('format-tab-title', function(tab, _, _, _, _, _)
    local pane = tab.active_pane

    local title = tab.active_pane.title
    -- フォルダ名 (cwd) タイトルは herdr のサイドバーが担うため無効化 (ペインタイトルに委譲)。
    -- herdr をやめる場合はコメント解除
    --[=[
    local pane_id = pane.pane_id
    if title_cache[pane_id] then
      title = title_cache[pane_id]
    end
    --]=]

    -- タブ幅 (wezterm.lua の tab_max_width = 32) に収まるよう省略記号込み
    -- 26 セルへ丸める。装飾は ' ' + アイコン + ' ' + 末尾 ' ' の 4 セル分
    -- (アイコンが 2 セル幅で描画される環境では 5 セル分) なので 26 + 5 = 31。
    -- バイト数 (#title) ではなく表示幅で測るのは、日本語タイトルが UTF-8 の
    -- 途中で切れて壊れるのを防ぐため
    if wezterm.column_width(title) > 26 then
      title = wezterm.truncate_right(title, 25) .. '…'
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

  -- Claude Code の通知（ターン終了 / 承認待ち）
  -- notify.sh が CC 本体の pts に OSC 1337 SetUserVar=CLAUDE_LAST_MSG を
  -- 直書きする。その user var 更新を user-var-changed で受けて toast を出す。
  -- bell ではなく user-var-changed を使うのは、CC 自身の turn 終了 BEL と
  -- notify.sh の書き込みのレースを避けるため。
  -- 注: macOSでは toast_notification が動作しないため hooks + terminal-notifier 経由
  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name ~= 'CLAUDE_LAST_MSG' then
      return
    end
    if not is_claude(pane) then
      return
    end
    if not value or value == '' then
      return
    end
    -- 複数セッション時にどのタブが終わったか分かるようタイトルにタブ番号を付ける
    local tab_id = get_tab_id(window, pane)
    local title = tab_id and ('Claude Code (タブ ' .. tab_id .. ')') or 'Claude Code'
    window:toast_notification(title, value, nil, 4000)
  end)
end

return M
