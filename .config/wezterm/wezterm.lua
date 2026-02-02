---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

local is_windows = wezterm.target_triple == 'x86_64-pc-windows-msvc'
local is_mac = wezterm.target_triple == 'x86_64-apple-darwin' or wezterm.target_triple == 'aarch64-apple-darwin'

local config = wezterm.config_builder()

config.audible_bell = 'Disabled'
config.visual_bell = {
  fade_in_duration_ms = 0,
  fade_out_duration_ms = 0,
}
config.notification_handling = 'AlwaysShow'
config.automatically_reload_config = true
config.disable_default_key_bindings = true
config.scrollback_lines = 10000
config.font = wezterm.font_with_fallback({
  'Firge35Nerd Console',
  'HackGen35 Console NF',
})
config.tab_bar_at_bottom = true
config.tab_max_width = 32
config.use_dead_keys = false
config.use_fancy_tab_bar = false
config.use_ime = true
config.window_decorations = 'RESIZE'
config.hide_tab_bar_if_only_one_tab = true

-- https://stackoverflow.com/questions/78738575/how-to-maximize-wezterm-on-startup
wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

local format = require('format')
format.apply()

local colors = require('colors')
colors.apply_to_config(config)

-- ファイルパスをクリックしてnvimで開く
-- https://zenn.dev/yashikota/articles/5e1f240d10d852
config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, 1, {
  regex = [[(\.?[\w/][\w/\.-]*\.\w+)(:\d+)?(:\d+)?]],
  format = 'editor://$PWD/$1$2$3',
})

wezterm.on('open-uri', function(window, pane, uri)
  local path = nil

  if uri:find('^editor://') then
    path = uri:gsub('^editor://', '')
  elseif uri:find('^file://') then
    path = uri:gsub('^file://', '')
  end

  if path then
    local start = path:find('$PWD', 1, true)
    if start then
      local cwd_uri = pane:get_current_working_dir()
      if cwd_uri and cwd_uri.file_path then
        local cwd = cwd_uri.file_path --[[@as string]]
        -- 末尾にスラッシュがなければ追加
        if not cwd:match('/$') then
          cwd = cwd .. '/'
        end
        path = path:gsub('$PWD/', cwd)
      end
    end

    -- ファイルパスと行番号を分離
    local file, line = path:match('^(.+):(%d+):?%d*$')
    if not file then
      file = path
      line = nil
    end

    local nvim_args = line and ('+' .. line .. ' "' .. file .. '"') or ('"' .. file .. '"')

    window:perform_action(
      wezterm.action.InputSelector({
        title = 'Open in nvim?',
        choices = {
          { label = 'Open: ' .. path, id = 'open' },
          { label = 'Cancel', id = 'cancel' },
        },
        action = wezterm.action_callback(function(win, p, id, _)
          if id == 'open' then
            win:perform_action(
              wezterm.action.SpawnCommandInNewTab({
                args = { '/bin/zsh', '-l', '-c', 'nvim ' .. nvim_args },
              }),
              p
            )
          end
        end),
      }),
      pane
    )
    return false
  end
end)

config.mouse_bindings = {
  -- シングルクリックではリンクを開かない（デフォルト動作を上書き）
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = wezterm.action.CompleteSelection('ClipboardAndPrimarySelection'),
  },
  -- ダブルクリックでリンクを開く
  {
    event = { Up = { streak = 2, button = 'Left' } },
    mods = 'NONE',
    action = wezterm.action.OpenLinkAtMouseCursor,
  },
}

if is_windows then
  require('windows').apply_to_config(config)
elseif is_mac then
  require('mac').apply_to_config(config)
end

return config
