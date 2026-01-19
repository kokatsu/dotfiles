-- https://www.arthurkoziel.com/json-schemas-in-neovim/

---@type vim.lsp.Config
local yamlls_config = {
  -- Override default filetypes to fix checkhealth warnings
  -- (nvim-lspconfig defaults include invalid 'yaml.docker-compose', 'yaml.gitlab', 'yaml.helm-values')
  filetypes = { 'yaml' },
  settings = {
    yaml = {
      schemas = {
        ['https://www.schemastore.org/pnpm-workspace.json'] = 'pnpm-workspace.yaml',
        ['https://raw.githubusercontent.com/compose-spec/compose-go/master/schema/compose-spec.json'] = {
          '**/compose.yaml',
          '**/compose.yml',
          '**/compose.*.yaml',
          '**/compose.*.yml',
          '**/docker-compose.yaml',
          '**/docker-compose.yml',
          '**/docker-compose.*.yaml',
          '**/docker-compose.*.yml',
        },
        ['https://www.rubyschema.org/rubocop.json'] = '.rubocop.yml',
      },
    },
  },
}

local taskgraph_schema_path = os.getenv('TASKGRAPH_SCHEMA_PATH')
if taskgraph_schema_path then
  yamlls_config.settings.yaml.schemas[taskgraph_schema_path] = '*.taskgraph.{yaml,yml}'
end

return yamlls_config
