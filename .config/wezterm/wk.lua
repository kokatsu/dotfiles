---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action
local wk = require('which-key.init')

local M = {}

local spec = {
  {
    key = 'p',
    desc = '+Pane',
    group = 'pane',
    children = {
      { key = 'h', desc = 'Split right', action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }) },
      { key = 'v', desc = 'Split down', action = act.SplitVertical({ domain = 'CurrentPaneDomain' }) },
      { key = 'x', desc = 'Close pane', action = act.CloseCurrentPane({ confirm = false }) },
      { key = 'z', desc = 'Toggle zoom', action = act.TogglePaneZoomState },
      {
        key = 'r',
        desc = '+Resize',
        group = 'pane_resize',
        -- リサイズは連続押下したいので action 後に key_table を維持
        sticky = true,
        children = {
          { key = 'h', desc = 'Left  -5', action = act.AdjustPaneSize({ 'Left', 5 }) },
          { key = 'l', desc = 'Right +5', action = act.AdjustPaneSize({ 'Right', 5 }) },
          { key = 'k', desc = 'Up    -5', action = act.AdjustPaneSize({ 'Up', 5 }) },
          { key = 'j', desc = 'Down  +5', action = act.AdjustPaneSize({ 'Down', 5 }) },
        },
      },
    },
  },
  {
    key = 't',
    desc = '+Tab',
    group = 'tab',
    children = {
      { key = 'n', desc = 'New tab', action = act.SpawnTab('CurrentPaneDomain') },
      { key = 'x', desc = 'Close tab', action = act.CloseCurrentTab({ confirm = false }) },
      { key = 'l', desc = 'Next tab', action = act.ActivateTabRelative(1) },
      { key = 'h', desc = 'Prev tab', action = act.ActivateTabRelative(-1) },
    },
  },
  { key = 'c', desc = 'Copy mode', action = act.ActivateCopyMode },
  { key = '/', desc = 'Quick select', action = act.QuickSelect },
  { key = 'P', desc = 'Command palette', action = act.ActivateCommandPalette },
  { key = 'L', desc = 'Debug overlay', action = act.ShowDebugOverlay },
}

function M.apply_to_config(config)
  wk.setup({
    leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1500 },
    hint = { key = '?', mods = 'SHIFT' },
    -- format.lua の update-status と left_status を取り合うのでデフォルト OFF
    status = false,
  })
  wk.register(spec)
  wk.apply(config)

  -- tmux 流 send-prefix: Ctrl+a Ctrl+a で literal Ctrl+a を pane に送る (readline 行頭等)
  table.insert(config.keys, {
    key = 'a',
    mods = 'LEADER|CTRL',
    action = act.SendKey({ key = 'a', mods = 'CTRL' }),
  })
end

return M
