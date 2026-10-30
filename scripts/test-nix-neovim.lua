local lazy_path, blink_path, peek_path, treesitter_path, pkl_path, after_path = unpack(arg)
assert(
  lazy_path and blink_path and peek_path and treesitter_path and pkl_path and after_path,
  'usage: test-nix-neovim.lua <lazy> <blink> <peek> <treesitter> <pkl> <after>'
)

local system = vim.system
vim.system = function(command, ...)
  assert(command[1] ~= 'curl', 'unexpected binary download')
  assert(not (command[1] == 'git' and (command[2] == 'clone' or command[2] == 'fetch')), 'unexpected Git download')
  return system(command, ...)
end

vim.opt.rtp:prepend(lazy_path)
require('lazy').setup({
  spec = {
    { name = 'blink.cmp', dir = blink_path, lazy = true },
    { name = 'peek.nvim', dir = peek_path, lazy = true },
    { 'nvim-treesitter/nvim-treesitter', name = 'nvim-treesitter', dir = treesitter_path, lazy = true },
    { name = 'pkl-neovim', dir = pkl_path, lazy = true },
  },
  local_spec = false,
  pkg = { enabled = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  lockfile = vim.fn.stdpath('state') .. '/test-lazy-lock.json',
})
local plugins = require('lazy.core.config').plugins
for _, name in ipairs({ 'lazy.nvim', 'blink.cmp', 'peek.nvim', 'nvim-treesitter', 'pkl-neovim' }) do
  assert(plugins[name]._.is_local, name .. ' must be local')
  assert(require('lazy.manage.task.git').fetch.skip(plugins[name]), name .. ' must skip fetch')
end

require('lazy.manage').restore({ wait = true, show = false })
for _, name in ipairs({ 'lazy.nvim', 'nvim-treesitter' }) do
  local restored = false
  for _, task in ipairs(plugins[name]._.tasks or {}) do
    assert(not task:has_errors(), name .. ': ' .. task:output())
    restored = true
  end
  assert(restored, name .. ' did not enter the restore pipeline')
end

local docs = require('lazy.manage.task.plugin').docs
local git_plugin = { _ = { is_local = false, dirty = true }, dir = vim.fn.tempname() }
assert(not docs.skip(git_plugin), 'updated Git plugin must still generate help tags')
vim.fn.mkdir(git_plugin.dir .. '/doc', 'p')
vim.fn.writefile(
  { '*nix-neovim-doc-test*  Help tag generation for writable plugins.' },
  git_plugin.dir .. '/doc/test.txt'
)
docs.run({ plugin = git_plugin, log = function() end })
assert(vim.fn.filereadable(git_plugin.dir .. '/doc/tags') == 1, 'Git plugin help tags were not generated')
vim.fn.delete(git_plugin.dir, 'rf')
print('Nix Neovim: restore skips local help tags and generates Git plugin tags')

vim.opt.rtp:prepend(blink_path)
require('blink.cmp.config').merge_with({
  fuzzy = { implementation = 'rust', prebuilt_binaries = { download = false } },
})
local completed = false
require('blink.cmp.fuzzy.download').ensure_downloaded(function(err, implementation)
  assert(not err, err)
  assert(implementation == 'rust', 'Rust fuzzy library was not selected')
  completed = true
end)
assert(
  vim.wait(5000, function()
    return completed
  end),
  'Rust fuzzy library did not initialize'
)
local matches = require('blink.cmp.fuzzy.rust').fuzzy_matched_indices('np', 2, { 'nix-preview' }, true)
assert(matches[1] and #matches[1] == 2, 'Rust fuzzy matching failed')
print('Nix Neovim: local plugins, fetch exclusion and Rust fuzzy matching passed')

vim.opt.rtp:prepend(treesitter_path)
vim.opt.rtp:append(after_path)
require('nvim-treesitter').setup({ install_dir = treesitter_path })
for _, language in ipairs({
  'bash',
  'css',
  'html',
  'javascript',
  'json',
  'lua',
  'markdown',
  'markdown_inline',
  'mermaid',
  'nix',
  'regex',
  'ruby',
  'rust',
  'scss',
  'sql',
  'svelte',
  'toml',
  'tsx',
  'typescript',
  'vim',
  'vue',
  'yaml',
  'pkl',
  'moonbit',
}) do
  assert(vim.treesitter.language.add(language), 'missing parser: ' .. language)
  local parser = vim.treesitter.get_string_parser('', language)
  assert(parser:parse()[1], 'parser failed: ' .. language)
  assert(vim.treesitter.query.get(language, 'highlights'), 'missing highlights: ' .. language)
  for _, kind in ipairs({ 'folds', 'indents', 'injections', 'textobjects' }) do
    vim.treesitter.query.get(language, kind)
  end
end
print('Nix Tree-sitter: 24 parsers and their queries passed')

local markdown = vim.treesitter.get_string_parser('```console\necho hello\n```\n', 'markdown')
markdown:parse(true)
assert(markdown:children().bash, 'custom console-to-bash Markdown injection missing')

local installer = require('nvim-treesitter.install')
installer.install = function()
  error('unexpected Pkl grammar installation')
end
installer.update = function()
  error('unexpected Pkl grammar update')
end
vim.opt.rtp:prepend(pkl_path)
vim.cmd.source(pkl_path .. '/plugin/pkl-neovim.vim')
assert(vim.treesitter.language.get_lang('pcf') == 'pkl', 'Pcf grammar association missing')
print('Nix Pkl: initialization without grammar acquisition passed')
