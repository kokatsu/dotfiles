--- プラットフォーム判定ユーティリティ
--- OS判定（静的）とWSL判定（動的）を提供
---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm

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

return M
