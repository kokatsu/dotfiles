-- WSL から Windows 側を操作するユーティリティ

local M = {}

--- URL を Windows 側の既定ブラウザで開く。
--- gsub は置換回数も返すため括弧で 1 値に絞る (cmd.exe に余分な引数を渡さない)
---@param url string
function M.open_url(url)
  vim.fn.jobstart({ 'cmd.exe', '/c', 'start', (url:gsub('&', '^&')) }, { detach = true })
end

return M
