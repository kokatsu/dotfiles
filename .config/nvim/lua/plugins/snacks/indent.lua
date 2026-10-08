local M = {}

--- @type snacks.indent.Config
M.opts = {
  -- inccommand のプレビューは内容が変わっても changedtick を進めないため、
  -- changedtick でキャッシュする空行判定が途中の空のプレビューから残り、
  -- 置換後の文字にガイドが重なる。: の入力中だけ描画しない。
  -- 後半は snacks の既定 filter と同じ条件
  filter = function(buf)
    return vim.fn.getcmdtype() ~= ':'
      and vim.g.snacks_indent ~= false
      and vim.b[buf].snacks_indent ~= false
      and vim.bo[buf].buftype == ''
  end,
  indent = {
    enabled = true,
    hl = {
      'SnacksIndent1',
      'SnacksIndent2',
      'SnacksIndent3',
      'SnacksIndent4',
      'SnacksIndent5',
      'SnacksIndent6',
      'SnacksIndent7',
      'SnacksIndent8',
    },
  },
  -- インデントガイド自体は残し、スコープが変わる度に走る 200ms の
  -- アニメーションだけ止める (duration は再度有効にするときのために残す)。
  animate = {
    enabled = false,
    duration = {
      step = 10,
      total = 200,
    },
  },
  --- @type snacks.indent.Scope.Config
  scope = {
    enabled = true,
    underline = true,
  },
}

return M
