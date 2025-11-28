-- Dashboard設定
local M = {}

local explorer = require('plugins.snacks.explorer')
local picker = require('plugins.snacks.picker')

M.opts = {
  preset = {
    ---@type snacks.dashboard.Item[] | fun(items:snacks.dashboard.Item[]): snacks.dashboard.Item[]?
    keys = {
      { icon = '󰙅 ', key = 'e', desc = 'File Explorer', action = explorer.action },
      { icon = ' ', key = 'f', desc = 'Smart Find Files', action = picker.smart_action },
      { icon = ' ', key = 'g', desc = 'Grep', action = picker.grep_action },
      { icon = '󰒲 ', key = 'l', desc = 'Lazy', action = ':Lazy', enabled = package.loaded.lazy ~= nil },
      { icon = ' ', key = 'q', desc = 'Quit', action = ':qa' },
      { icon = ' ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
      {
        icon = '󰁯 ',
        key = 's',
        desc = 'Restore Session',
        action = function()
          local cwd = vim.fn.getcwd()
          local session_name = cwd:gsub('/', '_'):gsub('^_', '')
          local sessions = require('mini.sessions')
          if sessions.detected[session_name] then
            sessions.read(session_name)
          else
            vim.notify('No session found for: ' .. cwd, vim.log.levels.WARN)
          end
        end,
      },
    },
  },
  formats = {
    terminal = { '%s', align = 'center' },
    version = { '%s', align = 'center' },
  },
  sections = {
    {
      section = 'header',
      height = 16,
      width = 10,
      enabled = function()
        return vim.fn.environ()['SSH_CLIENT'] ~= nil
      end,
    },
    {
      section = 'terminal',
      -- https://github.com/hpjansson/chafa
      cmd = 'chafa -p off --speed=0.9 --clear --passthrough=tmux --scale max "$XDG_CONFIG_HOME/nvim/assets/logo.gif"',
      indent = 12,
      ttl = 0,
      enabled = function()
        return vim.fn.executable('chafa') == 1 and vim.fn.environ()['SSH_CLIENT'] == nil
      end,
      height = 20,
      padding = 1,
    },
    { section = 'keys', gap = 1, padding = 1 },
    { section = 'startup' },
    function()
      local in_git = Snacks.git.get_root() ~= nil
      local cmds = {
        {
          title = 'Git Graph',
          icon = ' ',
          -- https://github.com/mlange-42/git-graph
          cmd = [[echo -e "$(git-graph --model catppuccin-mocha --style bold --color always --wrap 50 0 8 -f 'oneline' -n 30 --local)"]],
          indent = 1,
          height = 35,
        },
      }
      return vim.tbl_map(function(cmd)
        return vim.tbl_extend('force', {
          pane = 2,
          section = 'terminal',
          enabled = function()
            return in_git and vim.o.columns > 130
          end,
          padding = 1,
        }, cmd)
      end, cmds)
    end,
  },
}

return M
