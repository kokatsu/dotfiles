-- SQL 関連の補助ユーティリティ

local M = {}

-- UUID (8-4-4-4-12 桁の16進数) にマッチする Lua パターン。%x は [0-9A-Fa-f]
local UUID = '%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x'

--- 指定行範囲からすべての UUID を抽出し、SQL の `IN` 句用に
--- シングルクオートで囲んだカンマ区切りリストへ置換する (最終行はカンマ無し)。
--- 1行に複数 UUID がある場合も出現順にすべて拾う。
---@param line1 integer 1-based の開始行
---@param line2 integer 1-based の終了行
function M.quote_uuid_list(line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)

  local uuids = {}
  for _, line in ipairs(lines) do
    for uuid in line:gmatch(UUID) do
      uuids[#uuids + 1] = uuid
    end
  end

  if #uuids == 0 then
    vim.notify('UUID が見つかりませんでした', vim.log.levels.WARN)
    return
  end

  local out = {}
  for i, uuid in ipairs(uuids) do
    out[i] = ("'%s'%s"):format(uuid, i < #uuids and ',' or '')
  end

  vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, out)
  vim.notify(('%d 件の UUID を整形しました'):format(#uuids), vim.log.levels.INFO)
end

-- CSV エクスポートの出力先ファイル名 (固定)
local OUTPUT = 'result.csv'

--- カーソルを囲むクエリの行範囲を返す。
--- Markdown では fenced code block の fence を除いた中身、それ以外では
--- 空行で区切られた現在の段落をクエリとして扱う。
---@return integer? line1 1-based の開始行
---@return integer? line2 1-based の終了行
function M.current_query_range()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local line1, line2, error_kind = require('utils.codeblock').current_range()
  if line1 then
    return line1, line2
  end

  if vim.bo.filetype == 'markdown' then
    require('utils.codeblock').notify_range_error(error_kind)
    return
  end

  if not lines[cursor_line] or lines[cursor_line]:match('^%s*$') then
    vim.notify('カーソル行が空です', vim.log.levels.WARN)
    return
  end

  line1, line2 = cursor_line, cursor_line
  while line1 > 1 and not lines[line1 - 1]:match('^%s*$') do
    line1 = line1 - 1
  end
  while line2 < #lines and not lines[line2 + 1]:match('^%s*$') do
    line2 = line2 + 1
  end
  return line1, line2
end

local function is_identifier_byte(byte)
  return byte
    and (
      byte >= 128
      or (byte >= 48 and byte <= 57)
      or (byte >= 65 and byte <= 90)
      or byte == 95
      or byte == 36
      or (byte >= 97 and byte <= 122)
    )
end

local function is_identifier_start_byte(byte)
  return byte and (byte >= 128 or (byte >= 65 and byte <= 90) or byte == 95 or (byte >= 97 and byte <= 122))
end

local function dollar_quote_can_start(text, index)
  if not is_identifier_byte(text:byte(index - 1)) then
    return true
  end

  local token_start = index - 1
  while token_start > 1 and is_identifier_byte(text:byte(token_start - 1)) do
    token_start = token_start - 1
  end
  local first = text:byte(token_start)
  return first and first >= 48 and first <= 57
end

local function dollar_quote_delimiter(text, index)
  if text:sub(index, index + 1) == '$$' then
    return '$$'
  end

  local first = text:byte(index + 1)
  if not is_identifier_start_byte(first) then
    return
  end

  local cursor = index + 2
  while cursor <= #text and is_identifier_byte(text:byte(cursor)) and text:sub(cursor, cursor) ~= '$' do
    cursor = cursor + 1
  end
  if text:sub(cursor, cursor) == '$' then
    return text:sub(index, cursor)
  end
end

-- PostgreSQL の文字列・識別子・コメントを区別し、normal 状態にある
-- 文末セミコロンだけを返す。範囲選択と COPY 本文検証の両方で使う。
local function scan_sql(text)
  local state = 'normal'
  local block_depth = 0
  local dollar_delimiter
  local terminators = {}
  local last_significant
  local has_non_terminator = false
  local has_psql_meta_command = false
  local meta_commands = {}
  local i = 1

  while i <= #text do
    local char = text:sub(i, i)
    local next_char = text:sub(i + 1, i + 1)

    if state == 'normal' then
      if char:match('%s') then
        i = i + 1
      elseif char == '-' and next_char == '-' then
        state = 'line_comment'
        i = i + 2
      elseif char == '/' and next_char == '*' then
        state = 'block_comment'
        block_depth = 1
        i = i + 2
      elseif char == "'" then
        local previous = text:sub(i - 1, i - 1)
        local before_previous = text:byte(i - 2)
        state = (previous == 'E' or previous == 'e') and not is_identifier_byte(before_previous) and 'escape_string'
          or 'string'
        last_significant = i
        has_non_terminator = true
        i = i + 1
      elseif char == '"' then
        state = 'quoted_identifier'
        last_significant = i
        has_non_terminator = true
        i = i + 1
      elseif char == '$' and dollar_quote_can_start(text, i) then
        local delimiter = dollar_quote_delimiter(text, i)
        if delimiter then
          state = 'dollar_quote'
          dollar_delimiter = delimiter
          last_significant = i
          has_non_terminator = true
          i = i + #delimiter
        else
          last_significant = i
          has_non_terminator = true
          i = i + 1
        end
      elseif char == '\\' then
        state = 'psql_meta_command'
        meta_commands[#meta_commands + 1] = i
        has_psql_meta_command = true
        last_significant = i
        has_non_terminator = true
        i = i + 1
      elseif char == ';' then
        terminators[#terminators + 1] = i
        last_significant = i
        i = i + 1
      else
        last_significant = i
        has_non_terminator = true
        i = i + 1
      end
    elseif state == 'line_comment' or state == 'psql_meta_command' then
      if char == '\n' then
        state = 'normal'
      end
      i = i + 1
    elseif state == 'block_comment' then
      if char == '/' and next_char == '*' then
        block_depth = block_depth + 1
        i = i + 2
      elseif char == '*' and next_char == '/' then
        block_depth = block_depth - 1
        i = i + 2
        if block_depth == 0 then
          state = 'normal'
        end
      else
        i = i + 1
      end
    elseif state == 'string' then
      if char == "'" and next_char == "'" then
        i = i + 2
      elseif char == "'" then
        state = 'normal'
        last_significant = i
        i = i + 1
      else
        i = i + 1
      end
    elseif state == 'escape_string' then
      if char == '\\' or (char == "'" and next_char == "'") then
        i = i + 2
      elseif char == "'" then
        state = 'normal'
        last_significant = i
        i = i + 1
      else
        i = i + 1
      end
    elseif state == 'quoted_identifier' then
      if char == '"' and next_char == '"' then
        i = i + 2
      elseif char == '"' then
        state = 'normal'
        last_significant = i
        i = i + 1
      else
        i = i + 1
      end
    elseif state == 'dollar_quote' then
      if text:sub(i, i + #dollar_delimiter - 1) == dollar_delimiter then
        state = 'normal'
        last_significant = i + #dollar_delimiter - 1
        i = i + #dollar_delimiter
      else
        i = i + 1
      end
    end
  end

  -- 行末で終わる -- コメントは正常に閉じているものとして扱う。
  if state == 'line_comment' or state == 'psql_meta_command' then
    state = 'normal'
  end

  return {
    state = state,
    terminators = terminators,
    last_significant = last_significant,
    has_non_terminator = has_non_terminator,
    has_psql_meta_command = has_psql_meta_command,
    meta_commands = meta_commands,
  }
end

local function prepare_copy_stdout_body(text)
  local scan = scan_sql(text)
  if scan.state ~= 'normal' then
    return nil, '文字列・識別子・コメントの終端が見つからないためコピーを中止しました'
  end
  if scan.has_psql_meta_command then
    return nil, 'psql メタコマンドを含むためコピーを中止しました'
  end
  if #scan.terminators > 1 then
    return nil, '複数の SQL 文を含むためコピーを中止しました'
  end
  if #scan.terminators == 1 and scan.last_significant ~= scan.terminators[1] then
    return nil, 'SQL 文の途中にセミコロンがあるためコピーを中止しました'
  end
  if not scan.has_non_terminator then
    return nil, 'クエリが空です'
  end

  if #scan.terminators == 1 then
    local terminator = scan.terminators[1]
    local before = text:sub(1, terminator - 1):gsub('%s+$', '')
    local after = text:sub(terminator + 1)
    after = after:match('^%s*$') and '' or after:gsub('%s+$', '')
    text = before .. after
  end
  return text
end

local function cursor_byte_position(lines, text_length)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local position = 1
  for i = 1, cursor[1] - 1 do
    position = position + #lines[i] + 1
  end
  return math.min(position + cursor[2], text_length)
end

local function line_bounds(text, position)
  local previous_newline = text:sub(1, position - 1):match('.*()\n')
  local next_newline = text:find('\n', position, true)
  return (previous_newline or 0) + 1, next_newline and next_newline - 1 or #text
end

-- SQL バッファからカーソル位置の1文を取り出す。Normal モードでは曖昧な
-- 未終端文を推測せず、Visual 選択を促してクリップボードを保持する。
local function current_sql_statement_text()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, '\n')
  local scan = scan_sql(text)
  local cursor_position = cursor_byte_position(lines, #text)
  local selected_terminator

  for _, meta_command in ipairs(scan.meta_commands) do
    local line_start, line_end = line_bounds(text, meta_command)
    if line_start <= cursor_position and cursor_position <= line_end then
      return nil, 'psql メタコマンドを含む行ではクエリをコピーできません'
    end
  end

  -- 文末と同じ行の空白またはコメント上では、その文を選択する。
  local previous
  for _, terminator in ipairs(scan.terminators) do
    if terminator < cursor_position then
      previous = terminator
    else
      break
    end
  end
  if previous and not text:sub(previous, cursor_position):find('\n', 1, true) then
    local tail_scan = scan_sql(text:sub(previous + 1, cursor_position))
    if tail_scan.state == 'normal' and not tail_scan.has_non_terminator then
      selected_terminator = previous
    end
  end

  if not selected_terminator then
    for _, terminator in ipairs(scan.terminators) do
      if terminator >= cursor_position then
        selected_terminator = terminator
        break
      end
    end
  end

  if not selected_terminator then
    local message = scan.state ~= 'normal' and '文字列・識別子・コメントの終端が見つかりません'
      or '文末セミコロンがないためクエリ範囲を安全に判定できません'
    return nil, message .. '。Visual 選択で <leader>yg を実行してください'
  end

  local start_position = 1
  local previous_terminator
  for _, terminator in ipairs(scan.terminators) do
    if terminator < selected_terminator then
      start_position = terminator + 1
      previous_terminator = terminator
    else
      break
    end
  end

  -- 直前の文と同じ行にある空白・コメントは直前の文へ帰属させる。
  if previous_terminator then
    local _, previous_line_end = line_bounds(text, previous_terminator)
    local previous_tail = text:sub(previous_terminator + 1, previous_line_end)
    local previous_tail_scan = scan_sql(previous_tail)
    if previous_tail_scan.state == 'normal' and not previous_tail_scan.has_non_terminator then
      start_position = math.min(previous_line_end + 2, #text + 1)
    end
  end

  -- 独立した psql メタコマンド行は SQL 文の境界として扱う。
  for _, meta_command in ipairs(scan.meta_commands) do
    if meta_command < selected_terminator then
      local _, meta_line_end = line_bounds(text, meta_command)
      start_position = math.max(start_position, math.min(meta_line_end + 2, #text + 1))
    end
  end
  if start_position > cursor_position then
    return nil,
      'カーソル位置からクエリ範囲を安全に判定できません。対象の SQL 文にカーソルを移動してください'
  end

  local end_position = selected_terminator
  local newline = text:find('\n', selected_terminator + 1, true)
  local line_end = newline and newline - 1 or #text
  local trailing_text = text:sub(selected_terminator + 1, line_end)
  local trailing_scan = scan_sql(trailing_text)
  if trailing_scan.state == 'normal' and not trailing_scan.has_non_terminator and #trailing_scan.terminators == 0 then
    end_position = line_end
  end

  return vim.trim(text:sub(start_position, end_position))
end

-- 選択範囲を取得し、末尾の空行と末尾セミコロンを取り除いた行配列を返す
local function query_lines(line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  while #lines > 0 and lines[#lines]:match('^%s*$') do
    lines[#lines] = nil
  end
  if #lines > 0 then
    lines[#lines] = lines[#lines]:gsub('%s*;%s*$', '')
  end
  return lines
end

local function yank(text)
  vim.fn.setreg('+', text)
  vim.notify('クリップボードへコピーしました:\n' .. text, vim.log.levels.INFO)
end

local function yank_copy_stdout(text)
  local body, error_message = prepare_copy_stdout_body(text)
  if not body then
    vim.notify(error_message or 'クエリをコピーできませんでした', vim.log.levels.WARN)
    return
  end
  yank(("COPY (\n%s\n) TO STDOUT WITH CSV HEADER \\g '%s'"):format(body, OUTPUT))
end

--- 選択クエリを psql の `\copy (...) TO 'file' WITH CSV HEADER` へ変換し
--- クリップボード (+ レジスタ) へコピーする。
--- `\copy` は1行制約があるため改行は空白へ畳む。ただし行内の連続空白は
--- 文字列リテラルを壊さないよう保持し、`--` 行コメントを含む場合は1行化で
--- 後続句を巻き込むため変換を中止する (複数行を保持する to_copy_stdout_csv を使う)。
---@param line1 integer 1-based の開始行
---@param line2 integer 1-based の終了行
function M.to_copy_csv(line1, line2)
  local lines = query_lines(line1, line2)
  if #lines == 0 then
    vim.notify('クエリが空です', vim.log.levels.WARN)
    return
  end

  local parts = {}
  for _, line in ipairs(lines) do
    if line:find('%-%-') then
      vim.notify(
        '-- コメントを含むクエリは \\copy へ1行化できません。複数行を保持する <leader>yg を使ってください',
        vim.log.levels.WARN
      )
      return
    end
    local trimmed = vim.trim(line)
    if trimmed ~= '' then
      parts[#parts + 1] = trimmed
    end
  end

  yank(("\\copy (%s) TO '%s' WITH CSV HEADER"):format(table.concat(parts, ' '), OUTPUT))
end

--- 選択クエリを `COPY (...) TO STDOUT WITH CSV HEADER \g 'file'` へ変換する。
--- PostgreSQL の字句を検査し、複数文・未終端文字列・psql メタコマンドを
--- 含む場合はクリップボードを変更せず中止する。
---@param line1 integer 1-based の開始行
---@param line2 integer 1-based の終了行
function M.to_copy_stdout_csv(line1, line2)
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  while #lines > 0 and lines[1]:match('^%s*$') do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:match('^%s*$') do
    lines[#lines] = nil
  end
  if #lines == 0 then
    vim.notify('クエリが空です', vim.log.levels.WARN)
    return
  end
  yank_copy_stdout(table.concat(lines, '\n'))
end

--- カーソル位置のクエリを `\copy` コマンドへ変換してコピーする。
function M.current_query_to_copy_csv()
  local line1, line2 = M.current_query_range()
  if line1 and line2 then
    M.to_copy_csv(line1, line2)
  end
end

--- カーソル位置のクエリを複数行の `COPY ... \g` コマンドへ変換してコピーする。
--- SQL バッファでは文末セミコロンを境界に1文だけを抽出し、判定できない
--- 場合は Visual 選択を案内する。Markdown では fenced block を使用する。
function M.current_query_to_copy_stdout_csv()
  local line1, line2, error_kind = require('utils.codeblock').current_range()
  if line1 and line2 then
    M.to_copy_stdout_csv(line1, line2)
  elseif vim.bo.filetype == 'markdown' then
    require('utils.codeblock').notify_range_error(error_kind)
  elseif vim.bo.filetype == 'sql' then
    local text, error_message = current_sql_statement_text()
    if not text then
      vim.notify(error_message or 'クエリをコピーできませんでした', vim.log.levels.WARN)
      return
    end
    yank_copy_stdout(text)
  else
    line1, line2 = M.current_query_range()
    if line1 and line2 then
      M.to_copy_stdout_csv(line1, line2)
    end
  end
end

return M
