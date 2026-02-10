-- https://github.com/toppair/peek.nvim

local function inject_favicon(plugin_dir)
  local index_path = plugin_dir .. '/public/index.html'
  local lines = vim.fn.readfile(index_path)
  for _, line in ipairs(lines) do
    if line:match('rel="icon"') then
      return
    end
  end
  local favicon =
    [[  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🔍</text></svg>">]]
  for i, line in ipairs(lines) do
    if line:match('<title>') then
      table.insert(lines, i + 1, favicon)
      break
    end
  end
  vim.fn.writefile(lines, index_path)
end

return {
  'toppair/peek.nvim',
  event = { 'VeryLazy' },
  build = function(plugin)
    vim.system({ 'git', 'update-index', '--no-skip-worktree', 'public/index.html' }, { cwd = plugin.dir }):wait()
    vim.system({ 'git', 'checkout', '--', 'public/index.html' }, { cwd = plugin.dir }):wait()
    vim.system({ 'deno', 'task', '--quiet', 'build:fast' }, { cwd = plugin.dir }):wait()
    inject_favicon(plugin.dir)
    vim.system({ 'git', 'update-index', '--skip-worktree', 'public/index.html' }, { cwd = plugin.dir }):wait()
  end,
  config = function()
    local app = 'browser'
    if vim.fn.has('wsl') == 1 then
      app = { 'wslview' }
    end
    require('peek').setup({
      app = app,
    })
    vim.api.nvim_create_user_command('PeekOpen', require('peek').open, {})
    vim.api.nvim_create_user_command('PeekClose', require('peek').close, {})
  end,
}
