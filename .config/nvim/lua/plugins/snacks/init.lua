-- https://github.com/folke/snacks.nvim

local explorer = require('plugins.snacks.explorer')
local picker = require('plugins.snacks.picker')
local lazygit = require('plugins.snacks.lazygit')
local terminal = require('plugins.snacks.terminal')
local dashboard = require('plugins.snacks.dashboard')
local indent = require('plugins.snacks.indent')

return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    ---@class snacks.picker.matcher.Config
    matcher = picker.matcher_opts,
    ---@class snacks.explorer.Config
    explorer = explorer.opts,
    ---@class snacks.lazygit.Config
    lazygit = lazygit.opts,
    ---@class snacks.picker.Config
    picker = picker.opts,
    ---@class snacks.terminal.Config
    terminal = terminal.opts,
    ---@class snacks.picker.debug
    debug = {
      scores = false, -- show scores in the list
      leaks = false, -- show when pickers don't get garbage collected
      explorer = false, -- show explorer debug info
      files = false, -- show file debug info
      grep = false, -- show file debug info
      proc = false, -- show proc debug info
      extmarks = false, -- show extmarks errors
    },
    ---@class snacks.dashboard.Config
    dashboard = dashboard.opts,
    indent = indent.opts,
    -- Snacks.toggle.profiler():map(',pp'),
    -- Snacks.toggle.profiler_highlights():map(',ph'),
  },
  keys = {
    {
      '<leader>f',
      picker.smart_action,
      desc = 'Smart Find Files',
    },
    {
      '<leader>e',
      explorer.action,
      desc = 'File Explorer',
    },
    {
      '<leader>/',
      picker.grep_action,
      desc = 'Grep',
    },
    {
      '<leader>\\',
      picker.grep_no_regex_action,
      desc = 'Grep (No Regex)',
    },
    {
      '<C-\\>',
      function()
        Snacks.lazygit()
      end,
      desc = 'Lazygit',
    },
    {
      '<leader>T',
      function()
        Snacks.terminal()
      end,
      desc = 'Terminal',
    },
    {
      '<leader>D',
      function()
        Snacks.picker.diagnostics()
      end,
      desc = 'Diagnostics in Workspace',
    },
    {
      '<leader>b',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'Buffers',
    },
    {
      '<leader>gf',
      function()
        Snacks.picker.git_diff()
      end,
      desc = 'Git Diff (Files)',
    },
    {
      '<leader>gs',
      function()
        Snacks.picker.git_status()
      end,
      desc = 'Git Status',
    },
    {
      '<leader>gl',
      function()
        Snacks.picker.git_log()
      end,
      desc = 'Git Log',
    },
    {
      '<leader>gb',
      function()
        Snacks.picker.git_branches()
      end,
      desc = 'Git Branches',
    },
    {
      ',ps',
      function()
        Snacks.profiler.scratch()
      end,
      desc = 'Profiler Scratch',
    },
    -- Call Hierarchy
    {
      '<leader>ci',
      function()
        Snacks.picker.lsp_incoming_calls()
      end,
      desc = 'Incoming Calls',
    },
    {
      '<leader>co',
      function()
        Snacks.picker.lsp_outgoing_calls()
      end,
      desc = 'Outgoing Calls',
    },
  },
}
