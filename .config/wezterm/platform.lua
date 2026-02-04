--- プラットフォーム判定ユーティリティ
--- OS判定（静的）とWSL判定（動的）を提供
---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action

local M = {}

-- ==============================================================================
-- OS判定（静的：起動時に決定）
-- ==============================================================================

--- Windowsかどうか
M.is_windows = wezterm.target_triple == 'x86_64-pc-windows-msvc'

--- macOSかどうか
M.is_mac = wezterm.target_triple == 'x86_64-apple-darwin' or wezterm.target_triple == 'aarch64-apple-darwin'

--- Linuxかどうか
M.is_linux = wezterm.target_triple:find('linux') ~= nil

-- ==============================================================================
-- WSL判定（動的：ペインごとに判定）
-- ==============================================================================

--- WSLドメインかどうかを判定
---@param pane table WezTermのペインオブジェクト
---@return boolean WSLドメインの場合はtrue
function M.is_wsl_domain(pane)
  local domain = pane:get_domain_name()
  return domain and domain:match('^WSL:') ~= nil
end

--- Windows（非WSL）でのみ実行するアクションを作成
--- それ以外（macOS/Linux/WSL）の場合はfallbackを実行
---@param action table 実行するアクション
---@param fallback table|nil Windows以外の場合の動作: { key = 'x', mods = 'CTRL' } またはWezTermアクション
---@return table action_callback
function M.windows_non_wsl_action(action, fallback)
  return wezterm.action_callback(function(window, pane)
    if M.is_windows and not M.is_wsl_domain(pane) then
      window:perform_action(action, pane)
    elseif fallback then
      if fallback.key then
        window:perform_action(act.SendKey(fallback), pane)
      else
        window:perform_action(fallback, pane)
      end
    end
  end)
end

--- WSLドメインでのみ実行するアクションを作成
--- WSL以外の場合は何もしない、またはfallbackアクションを実行
---@param action table|function WSLで実行するアクション（functionの場合はwindow, paneを受け取る）
---@param fallback_action table|nil WSL以外で実行するアクション
---@return table action_callback
function M.wsl_only_action(action, fallback_action)
  return wezterm.action_callback(function(window, pane)
    if M.is_wsl_domain(pane) then
      if type(action) == 'function' then
        action(window, pane)
      else
        window:perform_action(action, pane)
      end
    elseif fallback_action then
      window:perform_action(fallback_action, pane)
    end
  end)
end

return M
