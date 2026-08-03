local M = {}

--- @type snacks.indent.Config
M.opts = {
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
