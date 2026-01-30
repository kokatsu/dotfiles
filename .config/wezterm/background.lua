---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

---@class BackgroundConfig
---@field file string ファイル名（拡張子なしの場合は .jpg, .png, .jpeg, .webp, .gif を自動判定）
---@field opacity? number デフォルトの透過度（0.0〜1.0、省略時は0.3）
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

---@diagnostic disable-next-line: missing-fields
local base_background = {
  source = {
    Color = '#1e1e2e',
  },
  opacity = 0.85,
  width = '100%',
  height = '100%',
}

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
local image_opacity_step = 0.05 ---@type number

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
  base_background,
}

M.default_background = default_background

-- InputSelector 用の choices を事前に生成（起動時に1回だけ）
local selector_choices = { { label = 'デフォルト（なし）', id = '0' } }
for i, bg in ipairs(background_images) do
  local label = bg.label .. ' (opacity: ' .. bg.opacity .. ')'
  table.insert(selector_choices, { label = label, id = tostring(i) })
end

-- 背景を適用する共通関数
---@param window any
---@param index number|nil nil の場合はデフォルト背景
local function apply_background(window, index)
  if index == nil then
    current_image_index = nil
    window:set_config_overrides({
      background = default_background,
    })
  else
    local bg = background_images[index]
    if bg then
      current_image_index = index
      image_opacity = bg.opacity
      window:set_config_overrides({
        background = {
          base_background,
          get_image_background(bg.path, image_opacity),
        },
      })
    end
  end
end

-- opacity を変更する共通関数
---@param window any
---@param delta number
local function adjust_opacity(window, delta)
  if not current_image_index then
    return
  end

  local new_opacity = image_opacity + delta
  if new_opacity < 0.0 or new_opacity > 1.0 then
    return
  end

  image_opacity = new_opacity
  local bg = background_images[current_image_index]
  if bg then
    window:set_config_overrides({
      background = {
        base_background,
        get_image_background(bg.path, image_opacity),
      },
    })
  end
end

-- 後方互換性のためイベントハンドラーは残す
wezterm.on('toggle-default-background', function(window, _)
  apply_background(window, nil)
end)

for i, _ in ipairs(background_images) do
  wezterm.on('toggle-background' .. i, function(window, _)
    apply_background(window, i)
  end)
end

wezterm.on('toggle-opacity-plus', function(window, _)
  adjust_opacity(window, image_opacity_step)
end)

wezterm.on('toggle-opacity-minus', function(window, _)
  adjust_opacity(window, -image_opacity_step)
end)

-- InputSelector 方式
M.apply_to_keys = function(keys, background_modifier, opacity_modifier)
  table.insert(keys, {
    key = 'b',
    mods = background_modifier,
    action = wezterm.action.InputSelector({
      title = '背景画像を選択',
      choices = selector_choices, -- 事前生成済みの choices を使用
      action = wezterm.action_callback(function(window, _, id, _)
        if id == '0' then
          apply_background(window, nil)
        elseif id then
          apply_background(window, tonumber(id))
        end
      end),
    }),
  })

  -- opacity 変更も直接処理（イベント経由をやめる）
  table.insert(keys, {
    key = 'UpArrow',
    mods = opacity_modifier,
    action = wezterm.action_callback(function(window, _)
      adjust_opacity(window, image_opacity_step)
    end),
  })

  table.insert(keys, {
    key = 'DownArrow',
    mods = opacity_modifier,
    action = wezterm.action_callback(function(window, _)
      adjust_opacity(window, -image_opacity_step)
    end),
  })
end

return M
