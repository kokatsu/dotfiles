---@type vim.lsp.Config
local jsonls_config = {
  settings = {
    json = {
      schemas = {
        {
          fileMatch = {
            '**/.claude/settings.json',
            '**/.claude/settings.local.json',
            '**/claude/settings.json',
            '**/claude/settings.local.json',
          },
          url = 'https://json.schemastore.org/claude-code-settings.json',
        },
        {
          fileMatch = {
            '**/package.json',
          },
          url = 'https://www.schemastore.org/package.json',
        },
      },
    },
  },
}

return jsonls_config
