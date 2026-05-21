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

--- 選択クエリを `COPY (...) TO STDOUT WITH CSV HEADER \g 'file'` へ変換し
--- クリップボード (+ レジスタ) へコピーする。
--- `\copy` と違い複数行のまま書けるので、元のクエリ整形を保持する。
---@param line1 integer 1-based の開始行
---@param line2 integer 1-based の終了行
function M.to_copy_stdout_csv(line1, line2)
  local lines = query_lines(line1, line2)
  if #lines == 0 then
    vim.notify('クエリが空です', vim.log.levels.WARN)
    return
  end
  local body = table.concat(lines, '\n')
  yank(("COPY (\n%s\n) TO STDOUT WITH CSV HEADER \\g '%s'"):format(body, OUTPUT))
end

return M
