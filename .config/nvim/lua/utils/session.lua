-- mini.sessions のセッション名 (mini.lua の自動保存と dashboard の復元で共有)

local M = {}

--- カレントディレクトリのパスをセッション名にする (スラッシュをアンダースコアに変換)
---@return string
function M.name()
  return (vim.fn.getcwd():gsub('/', '_'):gsub('^_', ''))
end

return M
