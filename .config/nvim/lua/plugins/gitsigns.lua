-- https://github.com/lewis6991/gitsigns.nvim

return {
  'lewis6991/gitsigns.nvim',
  config = function()
    require('gitsigns').setup({
      signs = {
        delete = { text = '_' },
        topdelete = { text = '‾' },
      },
      signs_staged = {
        delete = { text = '_' },
        topdelete = { text = '‾' },
      },
      numhl = true,
      current_line_blame = true,
      current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
      on_attach = function(bufnr)
        local gitsigns = require('gitsigns')

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map('n', ']g', function()
          if vim.wo.diff then
            return vim.cmd.normal({ ']g', bang = true })
          else
            gitsigns.nav_hunk('next')
          end
        end, { desc = 'Next Git Hunk' })
        map('n', '[g', function()
          if vim.wo.diff then
            return vim.cmd.normal({ '[g', bang = true })
          else
            gitsigns.nav_hunk('prev')
          end
        end, { desc = 'Previous Git Hunk' })
        map('n', ']G', function()
          if vim.wo.diff then
            return vim.cmd.normal({ ']G', bang = true })
          else
            gitsigns.nav_hunk('last')
          end
        end, { desc = 'Last Git Hunk' })
        map('n', '[G', function()
          if vim.wo.diff then
            return vim.cmd.normal({ '[G', bang = true })
          else
            gitsigns.nav_hunk('first')
          end
        end, { desc = 'First Git Hunk' })

        -- Actions
        map('n', '<leader>B', function()
          gitsigns.blame_line({ full = true })
        end, { desc = 'Git Blame Line' })
      end,
    })
  end,
}
