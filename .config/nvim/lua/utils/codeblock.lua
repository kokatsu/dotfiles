-- Markdown fenced code block helpers

local M = {}

local function opening_fence_marker(line)
  local marker, rest = line:match('^%s*([`]+)(.*)$')
  if not marker then
    marker, rest = line:match('^%s*([~]+)(.*)$')
  end
  if not marker or #marker < 3 then
    return
  end
  -- CommonMark では backtick fence の info string に backtick を含められない。
  if marker:sub(1, 1) == '`' and rest:find('`', 1, true) then
    return
  end
  return marker
end

local function is_closing_fence(line, opening_marker)
  local marker = line:match('^%s*([`]+)%s*$') or line:match('^%s*([~]+)%s*$')
  return marker and marker:sub(1, 1) == opening_marker:sub(1, 1) and #marker >= #opening_marker
end

--- カーソルを囲む fenced code block の fence を除いた行範囲を返す。
---@return integer? line1 1-based の開始行
---@return integer? line2 1-based の終了行
---@return 'not_found'|'empty'|'unclosed'? error_kind
function M.current_range()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local opening_line, opening_marker
  for i, line in ipairs(lines) do
    if not opening_line then
      local marker = opening_fence_marker(line)
      if marker then
        opening_line, opening_marker = i, marker
      end
    elseif is_closing_fence(line, opening_marker) then
      if opening_line <= cursor_line and cursor_line <= i then
        if opening_line + 1 >= i then
          return nil, nil, 'empty'
        end
        return opening_line + 1, i - 1
      end
      opening_line, opening_marker = nil, nil
    end
  end

  if opening_line and opening_line <= cursor_line then
    return nil, nil, 'unclosed'
  end
  return nil, nil, 'not_found'
end

---@param error_kind 'not_found'|'empty'|'unclosed'?
function M.notify_range_error(error_kind)
  local messages = {
    not_found = 'カーソルがコードブロック内にありません',
    empty = 'コードブロックが空です',
    unclosed = 'コードブロックの閉じ fence が見つかりません',
  }
  vim.notify(messages[error_kind] or 'コードブロックを取得できませんでした', vim.log.levels.WARN)
end

--- カーソルを囲む fenced code block の中身だけをクリップボードへコピーする。
function M.yank_current()
  local line1, line2, error_kind = M.current_range()
  if not line1 then
    M.notify_range_error(error_kind)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  vim.fn.setreg('+', table.concat(lines, '\n'))
  vim.notify('コードブロックの中身をクリップボードへコピーしました', vim.log.levels.INFO)
end

return M
