---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

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

local backgrounds_dir = wezterm.home_dir .. '/.config/assets/backgrounds'

-- local background_gif = backgrounds_dir .. '/background.gif'
-- local gif_background = nil
-- if file_exists(background_gif) then
--   gif_background = {
--     source = {
--       File = background_gif,
--     },
--     opacity = 0.3,
--     vertical_align = 'Bottom',
--     vertical_offset = '-1cell',
--     horizontal_align = 'Right',
--     repeat_x = 'NoRepeat',
--     repeat_y = 'NoRepeat',
--     width = '360px',
--     height = '360px',
--   }
-- end

-- 背景画像の配列（1~9まで対応）
local background_images = {}

-- 存在する画像ファイルのみを設定
for i = 1, 9 do
  local image_jpg = backgrounds_dir .. '/background' .. i .. '.jpg'
  local image_png = backgrounds_dir .. '/background' .. i .. '.png'
  if file_exists(image_jpg) then
    background_images[i] = image_jpg
  elseif file_exists(image_png) then
    background_images[i] = image_png
  end
end

local image_opacity = 0.3 ---@type number
local image_opacity_step = 0.05 ---@type number

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
  -- gif_background,
}

M.default_background = default_background

local background_image = nil

wezterm.on('toggle-default-background', function(window, _)
  background_image = nil
  window:set_config_overrides({
    background = default_background,
  })
end)

-- 背景画像切り替えの一般化された関数
local function create_background_toggle_handler(index)
  return function(window, _)
    background_image = background_images[index]
    window:set_config_overrides({
      background = {
        base_background,
        get_image_background(background_image, image_opacity),
      },
    })
  end
end

-- 1~9の背景画像切り替えイベントを登録
for i = 1, 9 do
  wezterm.on('toggle-background' .. i, create_background_toggle_handler(i))
end

wezterm.on('toggle-opacity-plus', function(window, _)
  if not background_image then
    return
  end

  if image_opacity + image_opacity_step <= 1.0 then
    image_opacity = image_opacity + image_opacity_step
  else
    return
  end

  window:set_config_overrides({
    background = {
      base_background,
      get_image_background(background_image, image_opacity),
    },
  })
end)

wezterm.on('toggle-opacity-minus', function(window, _)
  if not background_image then
    return
  end

  if image_opacity - image_opacity_step >= 0.0 then
    image_opacity = image_opacity - image_opacity_step
  else
    return
  end

  window:set_config_overrides({
    background = {
      base_background,
      get_image_background(background_image, image_opacity),
    },
  })
end)

-- InputSelector 方式
M.apply_to_keys = function(keys, background_modifier, opacity_modifier)
  table.insert(keys, {
    key = 'b',
    mods = background_modifier,
    action = wezterm.action.InputSelector({
      title = '背景画像を選択',
      choices = (function()
        local choices = { { label = 'デフォルト（なし）', id = '0' } }
        for i = 1, 9 do
          if background_images[i] then
            table.insert(choices, { label = '背景 ' .. i, id = tostring(i) })
          end
        end
        return choices
      end)(),
      action = wezterm.action_callback(function(window, pane, id, _)
        if id == '0' then
          window:perform_action(wezterm.action.EmitEvent('toggle-default-background'), pane)
        elseif id then
          window:perform_action(wezterm.action.EmitEvent('toggle-background' .. id), pane)
        end
      end),
    }),
  })

  table.insert(keys, {
    key = 'UpArrow',
    mods = opacity_modifier,
    action = wezterm.action.EmitEvent('toggle-opacity-plus'),
  })

  table.insert(keys, {
    key = 'DownArrow',
    mods = opacity_modifier,
    action = wezterm.action.EmitEvent('toggle-opacity-minus'),
  })
end

return M
