-- memo (dotfiles/bin/memo) 連携ユーティリティ

local M = {}

--- memo を `--no-edit` で実行し、作成されたファイルを開く。
--- memo は作成したパスを stdout に 1 行だけ出力するので、それをそのまま edit する
--- (memo 自身に $EDITOR を起動させると Neovim の中で Neovim が開いてしまう)。
--- 作成先は Neovim の cwd から見た Git リポジトリルート配下。
---@param opts? { local_memo?: boolean } local_memo=true で .local.md を作成する
function M.open(opts)
  opts = opts or {}

  local cmd = { 'memo', '--no-edit' }
  if opts.local_memo then
    cmd[#cmd + 1] = '--local'
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')
    if message == '' then
      message = ('memo が終了コード %d で失敗しました'):format(result.code)
    end
    vim.notify(message, vim.log.levels.ERROR)
    return
  end

  local path = vim.trim(result.stdout or '')
  if path == '' then
    vim.notify('memo がパスを出力しませんでした', vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(path))
end

return M
