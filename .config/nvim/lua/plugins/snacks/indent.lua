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
  animate = {
    enabled = false,
  },
  --- @type snacks.indent.Scope.Config
  scope = {
    enabled = true,
    underline = true,
  },
}

return M
