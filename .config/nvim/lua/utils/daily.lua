-- daily (dotfiles/bin/daily) 連携ユーティリティ

local M = {}

--- 本日の日記を開く。
--- daily は日記のパスを stdout に 1 行だけ出力するので、それをそのまま edit する
--- (daily 自身に $EDITOR を起動させると Neovim の中で Neovim が開いてしまう)。
--- 作成先は Neovim の cwd から見た Git リポジトリルート配下。
function M.open()
  local result = vim.system({ 'daily', '--no-edit' }, { text = true }):wait()
  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')
    if message == '' then
      message = ('daily が終了コード %d で失敗しました'):format(result.code)
    end
    vim.notify(message, vim.log.levels.ERROR)
    return
  end

  local path = vim.trim(result.stdout or '')
  if path == '' then
    vim.notify('daily がパスを出力しませんでした', vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(path))
end

return M
