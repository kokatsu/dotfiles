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
  { uri = 'file:///tmp/example.rb:12:3', file = '/tmp/example.rb', line = '+12' },
  { uri = 'file:///tmp/日本語 space.rb:24:8', file = '/tmp/日本語 space.rb', line = '+24' },
  { uri = 'file:///tmp/part:12/example.rb:24:8', file = '/tmp/part:12/example.rb', line = '+24' },
  {
    uri = 'file:///tmp/a\'"$(printf injected)`printf injected`.rb',
    file = '/tmp/a\'"$(printf injected)`printf injected`.rb',
  },
  { uri = 'editor://$PWD/test.rb', file = '/tmp/project $(printf cwd-probe)/test.rb' },
  { uri = 'editor://$PWD/test.rb:12:3', file = '/tmp/project $(printf cwd-probe)/test.rb', line = '+12' },
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
  -- Resolve Zsh from PATH for Linux CI and avoid login startup files.
  local cmd = { vim.fn.exepath('zsh'), '-f', '-c', args[4], args[5] }
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
handlers['open-uri'](window, pane, 'file:///tmp/report.html:12:3')
assert(vim.deep_equal(background_commands[2], { 'open', '/tmp/report.html' }), 'HTML line and column changed opener')
assert(handlers['open-uri'](window, pane, 'https://example.com') == nil, 'ordinary URL was intercepted')

local probe_commands = {}
local errors = {}
local resolve_ok = true
local resolve_output = '/work/日本語 project/report.html\n'
package.loaded.wezterm.run_child_process = function(args)
  table.insert(probe_commands, args)
  return resolve_ok, resolve_ok and resolve_output or '', 'resolution failed'
end
package.loaded.wezterm.log_error = function(message)
  table.insert(errors, message)
end
pane.get_user_vars = function()
  return { HERDR_CLIENT = '1' }
end
background_commands = {}
actions = {}
handlers['open-uri'](window, pane, 'editor://$PWD/report.html:12:3')
assert(#probe_commands == 1, 'Herdr HTML path was not resolved')
assert(vim.deep_equal(vim.list_slice(probe_commands[1], 6), { '--resolve-only', 'report.html' }))
assert(vim.deep_equal(background_commands[1], { 'open', '/work/日本語 project/report.html' }))
assert(#actions == 0, 'HTML opened the editor selector')

resolve_ok = false
handlers['open-uri'](window, pane, 'editor://$PWD/report.html')
assert(#background_commands == 1 and #errors == 1, 'failed resolution opened a browser or was not reported')
handlers['open-uri'](window, pane, 'file:///tmp/report.html')
assert(#probe_commands == 2, 'absolute HTML path unnecessarily queried Herdr')
assert(vim.deep_equal(background_commands[2], { 'open', '/tmp/report.html' }))

resolve_ok = true
resolve_output = 'report.html\n'
handlers['open-uri'](window, pane, 'editor://$PWD/report.html')
assert(#background_commands == 2 and #errors == 2, 'relative resolver output opened a browser')

package.loaded.wezterm.target_triple = 'x86_64-pc-windows-msvc'
local wsl_platform = dofile(wezterm_dir .. '/platform.lua')
package.loaded.platform.is_wsl_domain = wsl_platform.is_wsl_domain
package.loaded.platform.wsl_args = wsl_platform.wsl_args
pane.get_domain_name = function()
  return 'WSL:Ubuntu'
end
resolve_output = '/work/日本語 project/report.html\n'
handlers['open-uri'](window, pane, 'editor://$PWD/report.html')
local probe = probe_commands[#probe_commands]
assert(vim.deep_equal(vim.list_slice(probe, 1, 5), { 'wsl.exe', '-d', 'Ubuntu', '-e', '/bin/zsh' }))
assert(vim.deep_equal(vim.list_slice(probe, 10), { '--resolve-only', 'report.html' }))
assert(
  vim.deep_equal(
    background_commands[3],
    { 'wsl.exe', '-d', 'Ubuntu', '-e', 'wslview', '/work/日本語 project/report.html' }
  )
)
print(
  ('WezTerm links: %d filename cases, cancellation, HTML resolution, WSL argv and ordinary URL passed'):format(#cases)
)
