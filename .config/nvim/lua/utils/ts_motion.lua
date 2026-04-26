-- Treesitter textobject motion helpers
local M = {}

---@param query string  capture name (e.g. 'function.outer', 'class.outer')
---@param direction 'next' | 'prev'
function M.goto_textobject(query, direction)
  return function()
    local parsers = require('nvim-treesitter.parsers')

    local bufnr = vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)
    if not lang then
      return
    end

    local parser = parsers.get_parser(bufnr, lang)
    if not parser then
      return
    end

    local tree = parser:parse()[1]
    if not tree then
      return
    end

    local root = tree:root()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_row = cursor[1] - 1

    local matches = {}
    local query_obj = vim.treesitter.query.get(lang, 'textobjects')
    if not query_obj then
      return
    end

    for id, node in query_obj:iter_captures(root, bufnr, 0, -1) do
      local name = query_obj.captures[id]
      if name == query then
        local start_row = node:start()
        table.insert(matches, { row = start_row, node = node })
      end
    end

    table.sort(matches, function(a, b)
      return a.row < b.row
    end)

    local target = nil
    if direction == 'next' then
      for _, m in ipairs(matches) do
        if m.row > cursor_row then
          target = m
          break
        end
      end
    else
      for i = #matches, 1, -1 do
        if matches[i].row < cursor_row then
          target = matches[i]
          break
        end
      end
    end

    if target then
      vim.api.nvim_win_set_cursor(0, { target.row + 1, 0 })
    end
  end
end

return M
