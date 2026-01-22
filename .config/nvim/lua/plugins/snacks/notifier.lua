local M = {}

--- @type snacks.notifier.Config
M.opts = {
  timeout = 3000,
  width = { min = 40, max = 0.4 },
  height = { min = 1, max = 0.6 },
  margin = { top = 0, right = 1, bottom = 0 },
  padding = true,
  sort = { 'level', 'added' },
  level = vim.log.levels.TRACE,
  style = 'compact',
  top_down = true,
  date_format = '%R',
  refresh = 50,
}

return M
