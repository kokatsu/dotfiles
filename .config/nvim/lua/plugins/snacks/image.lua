-- https://github.com/folke/snacks.nvim/blob/main/docs/image.md

local M = {}

---@type snacks.image.Config
M.opts = {
  enabled = true,
  backend = 'kitty', -- WezTerm supports kitty graphics protocol
  doc = {
    -- enable image viewer for documents (markdown, etc.)
    enabled = true,
    inline = true,
    float = true,
    max_width = 80,
    max_height = 40,
  },
}

return M
