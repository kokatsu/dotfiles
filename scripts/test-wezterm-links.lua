-- Run: nvim --headless --clean -l scripts/test-wezterm-links.lua
local handlers = {}
local actions = {}
local background_commands = {}
local wezterm_dir = vim.fn.getcwd() .. '/.config/wezterm'

package.loaded.wezterm = {
  config_dir = wezterm_dir,
  config_builder = function()
    return {}
  end,
  font_with_fallback = function(fonts)
    return fonts
  end,
  default_hyperlink_rules = function()
    return {}
  end,
  on = function(event, fn)
    handlers[event] = fn
  end,
  format = function(parts)
    return parts
  end,
  action_callback = function(fn)
    return fn
  end,
  action = {
    InputSelector = function(value)
      return { selector = value }
    end,
    SpawnCommandInNewTab = function(value)
      return { spawn = value }
    end,
  },
  background_child_process = function(args)
    table.insert(background_commands, args)
  end,
}
package.loaded.platform = {
  is_mac = true,
  is_wsl_domain = function()
    return false
  end,
}
package.loaded.format = { apply = function() end }
package.loaded.colors = { apply_to_config = function() end }
package.loaded.mac = { apply_to_config = function() end }
dofile(wezterm_dir .. '/wezterm.lua')

local pane = {
  get_user_vars = function()
    return {}
  end,
  get_foreground_process_name = function()
    return '/bin/zsh'
  end,
  get_current_working_dir = function()
    return { file_path = '/tmp/project $(printf cwd-probe)' }
  end,
}
local window = {
  perform_action = function(_, action)
    table.insert(actions, action)
  end,
}

local cases = {
  { uri = 'file:///tmp/plain.rb', file = '/tmp/plain.rb' },
  { uri = 'file:///tmp/日本語 space.rb:12', file = '/tmp/日本語 space.rb', line = '+12' },
  {
    uri = 'file:///tmp/a\'"$(printf injected)`printf injected`.rb',
    file = '/tmp/a\'"$(printf injected)`printf injected`.rb',
  },
  { uri = 'editor://$PWD/test.rb', file = '/tmp/project $(printf cwd-probe)/test.rb' },
  { uri = 'editor://-option.rb', file = '-option.rb' },
}

local stub_dir = vim.fn.tempname()
vim.fn.mkdir(stub_dir, 'p')
vim.fn.writefile({ '#!/bin/sh', [[printf '%s\000' "$@"]] }, stub_dir .. '/nvim')
vim.fn.setfperm(stub_dir .. '/nvim', 'rwx------')

for _, case in ipairs(cases) do
  actions = {}
  assert(handlers['open-uri'](window, pane, case.uri) == false, 'file URI was not handled')
  actions[1].selector.action(window, pane, 'new-tab')
  local args = actions[2].spawn.args
  local expected = case.line and { case.line, '--', case.file } or { '--', case.file }
  assert(vim.deep_equal(vim.list_slice(args, 6), expected), 'wrong nvim argv: ' .. case.uri)
  -- Avoid login startup files while running the actual command and positional arguments.
  local cmd = { args[1], '-f', '-c', args[4], args[5] }
  vim.list_extend(cmd, vim.list_slice(args, 6))
  local result = vim.system(cmd, { env = { PATH = stub_dir .. ':' .. vim.env.PATH } }):wait()
  assert(result.code == 0, result.stderr)
  assert(result.stdout == table.concat(expected, '\0') .. '\0', 'shell reinterpreted filename: ' .. case.uri)
end
vim.fn.delete(stub_dir, 'rf')

actions = {}
handlers['open-uri'](window, pane, 'file:///tmp/cancel.rb')
actions[1].selector.action(window, pane, nil)
assert(#actions == 1, 'cancel opened a tab')
handlers['open-uri'](window, pane, 'file:///tmp/report.html')
assert(vim.deep_equal(background_commands[1], { 'open', '/tmp/report.html' }), 'HTML opener changed')
assert(handlers['open-uri'](window, pane, 'https://example.com') == nil, 'ordinary URL was intercepted')
print('WezTerm links: 5 filename cases, cancellation, HTML and ordinary URL passed')
