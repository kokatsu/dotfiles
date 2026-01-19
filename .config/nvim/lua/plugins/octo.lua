-- https://github.com/pwntester/octo.nvim

return {
  'pwntester/octo.nvim',
  cmd = 'Octo',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  keys = {
    { '<leader>on', '<cmd>Octo pr create<cr>', desc = 'PR Create' },
    { '<leader>op', '<cmd>Octo pr list<cr>', desc = 'PR List' },
    { '<leader>os', '<cmd>Octo pr search<cr>', desc = 'PR Search' },
    { '<leader>oc', '<cmd>Octo pr changes<cr>', desc = 'PR Changes' },
    { '<leader>od', '<cmd>Octo pr diff<cr>', desc = 'PR Diff' },
    { '<leader>or', '<cmd>Octo review start<cr>', desc = 'Start Review' },
    { '<leader>oR', '<cmd>Octo review submit<cr>', desc = 'Submit Review' },
    { '<leader>oi', '<cmd>Octo issue create<cr>', desc = 'Issue Create' },
    { '<leader>ol', '<cmd>Octo issue list<cr>', desc = 'Issue List' },
  },
  opts = {
    suppress_missing_scope = {
      projects_v2 = true,
    },
    picker = 'snacks',
    enable_builtin = true,
    default_to_projects_v2 = false,
    mappings_disable_default = false,
    gh_cmd = 'gh',
    gh_env = {},
    -- プロジェクト機能を使わない場合はこのクエリを無効化
    issues = {
      order_by = {
        field = 'CREATED_AT',
        direction = 'DESC',
      },
    },
    pull_requests = {
      order_by = {
        field = 'CREATED_AT',
        direction = 'DESC',
      },
    },
  },
}
