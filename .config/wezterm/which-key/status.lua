---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local colors = require('colors')

local M = {}

local installed = false
local fg = colors.palette.crust
local bg = colors.palette.peach

function M.install()
  if installed then
    return
  end
  installed = true

  -- ウィンドウ別に直前の表示キーを保持して、変化のないティックでの set_left_status を抑える
  local last = {}
  wezterm.on('update-status', function(window, _)
    local wid = window:window_id()
    local leader = window:leader_is_active()
    local tbl = window:active_key_table()
    local key = (leader and 'L' or '') .. (tbl or '')
    if last[wid] == key then
      return
    end
    last[wid] = key

    if not leader and not tbl then
      window:set_left_status('')
      return
    end

    local parts = {}
    if leader then
      table.insert(parts, 'LEADER')
    end
    if tbl then
      table.insert(parts, tbl)
    end

    window:set_left_status(wezterm.format({
      { Background = { Color = bg } },
      { Foreground = { Color = fg } },
      { Text = ' ' .. table.concat(parts, '  ') .. ' ' },
      'ResetAttributes',
    }))
  end)
end

return M
