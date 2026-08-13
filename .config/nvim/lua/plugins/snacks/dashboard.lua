-- Dashboard設定
local M = {}

local explorer = require('plugins.snacks.explorer')
local picker = require('plugins.snacks.picker')

-- root ごとの common git dir キャッシュ。linked worktree では .git がファイルになり
-- shallow マーカーは common git dir 側に置かれるため、rev-parse で一度だけ解決する。
local common_git_dirs = {}

-- shallow 判定。git の起動は root ごとに初回のみで、以降の再評価
-- (dashboard はリサイズごとにセクションを再解決する) は fs_stat だけで済む。
local function is_shallow(root)
  local dir = common_git_dirs[root]
  if dir == nil then
    if vim.fn.executable('git') ~= 1 then
      return true
    end
    local result = vim.system({ 'git', '-C', root, 'rev-parse', '--git-common-dir' }, { text = true }):wait()
    dir = result.code == 0 and vim.trim(result.stdout) or false
    if dir and not vim.startswith(dir, '/') then
      dir = root .. '/' .. dir
    end
    common_git_dirs[root] = dir
  end
  return dir == false or vim.uv.fs_stat(dir .. '/shallow') ~= nil
end

M.opts = {
  preset = {
    ---@type snacks.dashboard.Item[] | fun(items:snacks.dashboard.Item[]): snacks.dashboard.Item[]?
    keys = {
      -- nf-md-file_tree
      { icon = '󰙅 ', key = 'e', desc = 'File Explorer', action = explorer.action },
      -- nf-md-file_search
      { icon = '󰱼 ', key = 'f', desc = 'Smart Find Files', action = picker.smart_action },
      -- nf-md-text_search
      { icon = '󱎸 ', key = 'g', desc = 'Grep', action = picker.grep_action },
      -- nf-md-sleep
      { icon = '󰒲 ', key = 'l', desc = 'Lazy', action = ':Lazy', enabled = package.loaded.lazy ~= nil },
      -- nf-md-exit_to_app
      { icon = '󰈆 ', key = 'q', desc = 'Quit', action = ':qa' },
      -- nf-md-undo
      { icon = '󰕌 ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
      {
        icon = '󰁯 ', -- nf-md-backup_restore
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
      -- 公式 docs (https://github.com/folke/snacks.nvim/blob/main/docs/dashboard.md)
      cmd = 'chafa -p off --format symbols --symbols wedge --size 40x40 "$HOME/.config/assets/logos/logo.png"; sleep .1',
      indent = 12,
      ttl = 0,
      enabled = function()
        local logo_path = vim.fn.expand('$HOME/.config/assets/logos/logo.png')
        return vim.fn.executable('chafa') == 1
          and vim.fn.environ()['SSH_CLIENT'] == nil
          and vim.fn.filereadable(logo_path) == 1
      end,
      height = 20,
      padding = 1,
    },
    { section = 'keys', gap = 1, padding = 1 },
    { section = 'startup' },
    {
      pane = 2,
      section = 'terminal',
      title = 'Git Graph',
      icon = ' ',
      -- https://github.com/mlange-42/git-graph (original)
      -- https://github.com/kokatsu/git-graph (fork, using this)
      cmd = [[git-graph --model catppuccin-mocha --style bold --color always --wrap 50 0 8 --format 'oneline' --max-count 30 --local --highlight-head 'bold,black,bg:bright_yellow']],
      indent = 1,
      height = 35,
      ttl = 0,
      padding = 1,
      enabled = function()
        -- 幅が足りない画面ではリポジトリ状態の判定自体を省く
        if vim.o.columns <= 130 or vim.fn.executable('git-graph') ~= 1 then
          return false
        end
        -- git-graph は cwd で走るため、判定の起点も cwd に固定する
        local root = Snacks.git.get_root(vim.uv.cwd())
        -- shallow リポジトリでは git-graph が履歴を辿れないため隠す
        return root ~= nil and not is_shallow(root)
      end,
    },
  },
}

return M
