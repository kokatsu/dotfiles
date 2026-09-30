---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

local colors = require('colors')

---@class BackgroundConfig
---@diagnostic disable-next-line: duplicate-doc-field
---@field file string ファイル名（拡張子なしの場合は .jpg, .png, .jpeg, .webp, .gif を自動判定）
---@diagnostic disable-next-line: duplicate-doc-field
---@field opacity? number デフォルトの透過度（0.0〜1.0、省略時は0.3）
---@diagnostic disable-next-line: duplicate-doc-field
---@field label? string InputSelectorで表示するラベル（省略時はファイル名）

-- backgrounds.lua が存在しない場合は空のテーブルを使用
---@type BackgroundConfig[]
local background_config
local ok, loaded = pcall(require, 'backgrounds')
if ok then
  background_config = loaded
else
  background_config = {}
end

local M = {}

local function file_exists(path)
  local file = io.open(path, 'r')
  if file then
    file:close()
    return true
  end
  return false
end

-- base レイヤーの不透明度（画像未選択時の opacity 変更対象）
---@diagnostic disable-next-line: undefined-global
local base_opacity = __BASE_OPACITY__ ---@type number

-- base レイヤーを生成（opacity を書き換えるため毎回新しいテーブルを生成）
local function get_base_background()
  ---@diagnostic disable-next-line: missing-fields
  return {
    source = {
      Color = '__CATPPUCCIN_BASE__',
    },
    opacity = base_opacity,
    width = '100%',
    height = '100%',
  }
end

local backgrounds_dir = (os.getenv('USERPROFILE') or wezterm.home_dir) .. '/.config/assets/backgrounds'

local DEFAULT_OPACITY = 0.3

--- ファイルパスを解決（拡張子なしの場合は .jpg, .png を試す）
---@param file string
---@return string|nil
local function resolve_image_path(file)
  -- 拡張子付きの場合はそのままチェック
  if file:match('%.[^.]+$') then
    local path = backgrounds_dir .. '/' .. file
    if file_exists(path) then
      return path
    end
    return nil
  end

  -- 拡張子なしの場合は .jpg, .png を試す
  local extensions = { '.jpg', '.png', '.jpeg', '.webp', '.gif' }
  for _, ext in ipairs(extensions) do
    local path = backgrounds_dir .. '/' .. file .. ext
    if file_exists(path) then
      return path
    end
  end
  return nil
end

-- 背景画像の配列（設定リストから生成、存在するファイルのみ連続したインデックスで格納）
---@type { path: string, opacity: number, label: string }[]
local background_images = {}

-- 存在する画像ファイルのみを設定
for _, config in ipairs(background_config) do
  local path = resolve_image_path(config.file)
  if path then
    table.insert(background_images, {
      path = path,
      opacity = config.opacity or DEFAULT_OPACITY,
      label = config.label or config.file,
    })
  end
end

-- 現在の状態
local current_image_index = nil ---@type number|nil
local image_opacity = DEFAULT_OPACITY ---@type number
local opacity_step = 0.05 ---@type number

-- 背景設定を生成（キャッシュなし、毎回新しいテーブルを生成）
---@param background_image string
---@param opacity number
local function get_image_background(background_image, opacity)
  return {
    source = {
      File = background_image,
    },
    opacity = opacity,
    width = '100%',
    height = '100%',
  }
end

local default_background = {
  get_base_background(),
}

M.default_background = default_background

local label_width = 0
for _, bg in ipairs(background_images) do
  label_width = math.max(label_width, wezterm.column_width(bg.label))
end

local BAR_CELLS = 10

---@param opacity number
local function opacity_bar(opacity)
  local filled = math.floor(opacity * BAR_CELLS + 0.5)
  return string.rep('▰', filled)
    .. string.rep('▱', BAR_CELLS - filled)
    .. string.format(' %3d%%', math.floor(opacity * 100 + 0.5))
end

-- InputSelector はカーソル行を反転表示し、文字色がそのまま背景色になる。
-- 行内で色を変えるとカーソル行の背景がまだらになるため、1 行を単色で描く
---@param active boolean
---@param icon string
---@param label string
---@param trailing? string
local function choice_label(active, icon, label, trailing)
  return wezterm.format({
    { Foreground = { Color = active and colors.palette.accent or colors.palette.text } },
    { Attribute = { Intensity = active and 'Bold' or 'Normal' } },
    {
      Text = (active and '● ' or '  ')
        .. icon
        .. '  '
        .. wezterm.pad_right(label, label_width)
        .. '  '
        .. (trailing or ''),
    },
    'ResetAttributes',
  })
end

-- 現在の選択に印を付けるため、開くたびに生成する
local function build_choices()
  local choices = {
    {
      label = choice_label(current_image_index == nil, wezterm.nerdfonts.md_image_off, 'デフォルト（なし）'),
      id = '0',
    },
  }
  for i, bg in ipairs(background_images) do
    local active = current_image_index == i
    local opacity = active and image_opacity or bg.opacity
    table.insert(choices, {
      label = choice_label(active, wezterm.nerdfonts.md_image, bg.label, opacity_bar(opacity)),
      id = tostring(i),
    })
  end
  return choices
end

-- 現在の状態から背景オーバーライドを再適用する
---@param window any
local function refresh_background(window)
  local layers = { get_base_background() }
  local bg = current_image_index and background_images[current_image_index]
  if bg then
    table.insert(layers, get_image_background(bg.path, image_opacity))
  end
  window:set_config_overrides({
    background = layers,
  })
end

-- 背景を適用する共通関数
---@param window any
---@param index number|nil nil の場合はデフォルト背景
local function apply_background(window, index)
  local bg = index and background_images[index]
  if index ~= nil and not bg then
    return
  end

  current_image_index = index
  if bg then
    image_opacity = bg.opacity
  end
  refresh_background(window)
end

-- opacity を変更する共通関数
-- 画像選択中は画像レイヤー、未選択時は base レイヤーの opacity を動かす
---@param window any
---@param delta number
local function adjust_opacity(window, delta)
  local current = current_image_index and image_opacity or base_opacity
  -- 加算の誤差が累積すると下限 0.0 / 上限 1.0 に到達できなくなるため、
  -- opacity_step の桁 (0.01 刻み) に丸めてから範囲判定する
  local new_opacity = math.floor((current + delta) * 100 + 0.5) / 100
  if new_opacity < 0.0 or new_opacity > 1.0 then
    return
  end

  if current_image_index then
    image_opacity = new_opacity
  else
    base_opacity = new_opacity
  end
  refresh_background(window)
end

-- InputSelector 方式
M.apply_to_keys = function(keys, background_modifier, opacity_modifier)
  table.insert(keys, {
    key = 'b',
    mods = background_modifier,
    action = wezterm.action_callback(function(window, pane)
      window:perform_action(
        ---@diagnostic disable-next-line: missing-fields
        wezterm.action.InputSelector({
          title = '背景画像を選択',
          description = '背景画像を選択    Enter: 適用  /: 検索  Esc: 閉じる',
          fuzzy_description = '検索: ',
          choices = build_choices(),
          action = wezterm.action_callback(function(win, _, id, _)
            if id == '0' then
              apply_background(win, nil)
            elseif id then
              apply_background(win, tonumber(id))
            end
          end),
        }),
        pane
      )
    end),
  })

  -- opacity 変更も直接処理（イベント経由をやめる）
  table.insert(keys, {
    key = 'UpArrow',
    mods = opacity_modifier,
    action = wezterm.action_callback(function(window, _)
      adjust_opacity(window, opacity_step)
    end),
  })

  table.insert(keys, {
    key = 'DownArrow',
    mods = opacity_modifier,
    action = wezterm.action_callback(function(window, _)
      adjust_opacity(window, -opacity_step)
    end),
  })
end

return M
