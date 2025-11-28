-- https://github.com/zbirenbaum/copilot.lua
-- https://qiita.com/haw_ohnuma/items/1ec8ef5091b440cbb8bd

return {
  'zbirenbaum/copilot.lua',
  cmd = 'Copilot',
  config = function()
    require('copilot').setup({
      suggestion = { enabled = false },
      panel = { enabled = false },
      copilot_node_command = 'node',
      -- https://zenn.dev/kawarimidoll/books/6064bf6f193b51/viewer/90a5be
      filetypes = {
        ['*'] = function()
          local file_name = vim.fs.basename(vim.api.nvim_buf_get_name(0))
          local disable_patterns = {
            'env',
            'conf',
            'local',
            'private',
          }
          return vim.iter(disable_patterns):all(function(pattern)
            return not string.match(file_name, pattern)
          end)
        end,
      },
    })
  end,
}
