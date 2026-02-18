-- https://github.com/lewis6991/gitsigns.nvim

return {
  'lewis6991/gitsigns.nvim',
  config = function()
    require('gitsigns').setup({
      signs = {
        add = { text = '┃' },
        change = { text = '┃' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
        untracked = { text = '┆' },
      },
      signs_staged = {
        add = { text = '┃' },
        change = { text = '┃' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
        untracked = { text = '┆' },
      },
      signs_staged_enable = true,
      signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
      numhl = true, -- Toggle with `:Gitsigns toggle_numhl`
      linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
      word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
      watch_gitdir = {
        follow_files = true,
      },
      auto_attach = true,
      attach_to_untracked = false,
      current_line_blame = true, -- Toggle with `:Gitsigns toggle_current_line_blame`
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
        delay = 1000,
        ignore_whitespace = false,
        virt_text_priority = 100,
        use_focus = true,
      },
      current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
      sign_priority = 6,
      update_debounce = 100,
      status_formatter = nil, -- Use default
      max_file_length = 40000, -- Disable if file is longer than this (in lines)
      preview_config = {
        -- Options passed to nvim_open_win
        border = 'single',
        style = 'minimal',
        relative = 'cursor',
        row = 0,
        col = 1,
      },
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
