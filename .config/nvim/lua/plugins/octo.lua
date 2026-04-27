-- Upstream: https://github.com/pwntester/octo.nvim
-- Fork:     https://github.com/kokatsu/octo.nvim
--
-- Pinned to a personal fork branch that guards `M.load_buffer`'s async
-- success callback against wiped buffers. Without it, snacks picker
-- previews trigger `BufReadCmd` -> `load_buffer` for `octo://*` buffers,
-- and the GraphQL response can return after the preview buffer is wiped,
-- raising `Invalid buffer id` from `nvim_buf_call` (init.lua:111).
-- Drop the `branch` line and switch back to `pwntester/octo.nvim` once
-- the fix is merged upstream.

return {
  'kokatsu/octo.nvim',
  branch = 'fix/load-buffer-invalid-bufnr',
  cmd = 'Octo',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  init = function()
    -- Register markdown parser for octo filetype to enable snacks.nvim image support
    vim.treesitter.language.register('markdown', 'octo')
  end,
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
  },
}
