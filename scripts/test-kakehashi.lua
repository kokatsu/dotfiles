local binary, config_file, grammar_path, lsp_config = unpack(arg)
assert(
  binary and config_file and grammar_path and lsp_config,
  'usage: test-kakehashi.lua <binary> <config> <grammars> <lsp-config>'
)

local config = dofile(lsp_config)
local messages = {}
local id = assert(vim.lsp.start({
  name = 'kakehashi-nix-test',
  cmd = { binary, '--config-file', config_file },
  init_options = vim.tbl_extend('force', config.init_options, { languageServers = vim.empty_dict() }),
  handlers = {
    ['window/logMessage'] = function(_, message)
      if message.type <= vim.lsp.protocol.MessageType.Warning then
        messages[#messages + 1] = message.message
      end
    end,
  },
}, { attach = false }))
local client = assert(vim.lsp.get_client_by_id(id))
assert(
  vim.wait(10000, function()
    return client.initialized
  end),
  'kakehashi initialization timed out'
)

local function request(method, params)
  local response, err = client:request_sync(method, params, 10000)
  assert(response, err)
  assert(not response.err, vim.inspect(response.err))
  assert(
    response.result ~= nil and response.result ~= vim.NIL,
    method .. ' returned no result: ' .. vim.inspect(params) .. '\n' .. table.concat(messages, '\n')
  )
  return response.result
end

local settings = request('kakehashi/internal/effectiveConfiguration', {}).settings
assert(vim.deep_equal(settings.searchPaths, { grammar_path }), 'unexpected parser search paths')
assert(settings.languages._.autoInstall == false, 'automatic installation must be disabled')

local function open(language, text)
  local uri = 'file:///tmp/kakehashi-nix-test-' .. language
  client:notify('textDocument/didOpen', {
    textDocument = { uri = uri, languageId = language, version = 1, text = text },
  })
  return { uri = uri }
end

local languages = {
  'bash',
  'c',
  'css',
  'd',
  'diff',
  'gitignore',
  'go',
  'html',
  'ini',
  'javascript',
  'json',
  'json5',
  'latex',
  'lua',
  'make',
  'markdown',
  'markdown_inline',
  'mermaid',
  'moonbit',
  'nix',
  'pascal',
  'perl',
  'pkl',
  'po',
  'powershell',
  'python',
  'r',
  'regex',
  'ruby',
  'rust',
  'scss',
  'sql',
  'svelte',
  'tmux',
  'toml',
  'tsx',
  'typescript',
  'typst',
  'vim',
  'vue',
  'xml',
  'yaml',
  'zig',
}
for _, language in ipairs(languages) do
  local document = open(language, 'value = 42\n')
  request('kakehashi/node', { textDocument = document, position = { line = 0, character = 0 } })
  local captures = request('kakehashi/captures/full', { textDocument = document, kind = 'highlights' })
  assert(#captures.skipped == 0, language .. ': invalid highlight patterns: ' .. vim.inspect(captures.skipped))
  client:notify('textDocument/didClose', { textDocument = document })
end

local document = open('markdown', '# Heading\n\n```console\necho hello\n```\n\n```lua\nlocal value = 42\n```\n')
local captures = request('kakehashi/captures/full', { textDocument = document, kind = 'highlights', injection = true })
local highlighted = {}
for _, match in ipairs(captures.matches) do
  highlighted[match.language] = true
end
assert(highlighted.markdown and highlighted.lua, 'Markdown injections missing: ' .. vim.inspect(highlighted))
local tokens = request('textDocument/semanticTokens/full', { textDocument = document })
assert(#tokens.data > 0, 'Markdown semantic tokens missing')
local line = 0
local console_highlighted = false
for index = 1, #tokens.data, 5 do
  line = line + tokens.data[index]
  console_highlighted = console_highlighted or line == 3
end
assert(console_highlighted, 'console-to-bash semantic tokens missing')
assert(#messages == 0, table.concat(messages, '\n'))
client:stop()
assert(
  vim.wait(5000, function()
    return client:is_stopped()
  end),
  'kakehashi shutdown timed out'
)
assert(vim.fn.glob(vim.env.XDG_DATA_HOME .. '/kakehashi/parser/*') == '', 'unexpected parser installation')
print(('Nix kakehashi: %d parsers, highlight queries and Markdown injections passed'):format(#languages))
