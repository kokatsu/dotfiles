local M = {}

--- @type snacks.words.Config
M.opts = {
  debounce = 200,
  notify_jump = false,
  notify_end = true,
  foldopen = true,
  jumplist = true,
  modes = { 'n', 'i', 'c' },
}

return M
