-- https://github.com/folke/snacks.nvim

local bigfile = require('plugins.snacks.bigfile')
local bookmarks = require('plugins.snacks.bookmarks')
local bufdelete = require('plugins.snacks.bufdelete')
local dashboard = require('plugins.snacks.dashboard')
local explorer = require('plugins.snacks.explorer')
local gitbrowse = require('plugins.snacks.gitbrowse')
local image = require('plugins.snacks.image')
local indent = require('plugins.snacks.indent')
local lazygit = require('plugins.snacks.lazygit')
local notifier = require('plugins.snacks.notifier')
local picker = require('plugins.snacks.picker')
local quickfile = require('plugins.snacks.quickfile')
local scroll = require('plugins.snacks.scroll')
local terminal = require('plugins.snacks.terminal')
local words = require('plugins.snacks.words')

return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    ---@class snacks.bigfile.Config
    bigfile = bigfile.opts,
    ---@class snacks.bufdelete.Config
    bufdelete = bufdelete.opts,
    ---@class snacks.gitbrowse.Config
    gitbrowse = gitbrowse.opts,
    ---@class snacks.image.Config
    image = image.opts,
    ---@class snacks.notifier.Config
    notifier = notifier.opts,
    ---@class snacks.quickfile.Config
    quickfile = quickfile.opts,
    ---@class snacks.scroll.Config
    scroll = scroll.opts,
    ---@class snacks.words.Config
    words = words.opts,
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
  },
  keys = {
    -- Profiler
    {
      ',pp',
      function()
        Snacks.toggle.profiler():toggle()
      end,
      desc = 'Toggle Profiler',
    },
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
      '<leader>m',
      bookmarks.action,
      desc = 'Bookmarks',
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
      '<leader>go',
      function()
        Snacks.gitbrowse()
      end,
      desc = 'Git Browse',
      mode = { 'n', 'v' },
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
    -- Notifier
    {
      '<leader>n',
      function()
        Snacks.notifier.show_history()
      end,
      desc = 'Notification History',
    },
    -- Words
    {
      ']]',
      function()
        Snacks.words.jump(1, true)
      end,
      desc = 'Next Reference',
      mode = { 'n', 't' },
    },
    {
      '[[',
      function()
        Snacks.words.jump(-1, true)
      end,
      desc = 'Prev Reference',
      mode = { 'n', 't' },
    },
    -- Bufdelete
    {
      '<leader>bd',
      function()
        Snacks.bufdelete()
      end,
      desc = 'Delete Buffer',
    },
    {
      '<leader>bo',
      function()
        Snacks.bufdelete.other()
      end,
      desc = 'Delete Other Buffers',
    },
  },
}
