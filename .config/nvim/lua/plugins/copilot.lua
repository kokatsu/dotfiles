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
    })
  end,
}
