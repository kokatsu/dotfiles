-- https://www.arthurkoziel.com/json-schemas-in-neovim/

---@type vim.lsp.Config
local yamlls_config = {
  -- Override default filetypes to fix checkhealth warnings
  -- (nvim-lspconfig defaults include invalid 'yaml.docker-compose', 'yaml.gitlab', 'yaml.helm-values')
  filetypes = { 'yaml' },
  -- Workaround: Neovim's _register_dynamic crashes when yamlls dynamically registers
  -- workspace/didChangeConfiguration (not in _request_name_to_server_capability table,
  -- so _registration_provider returns nil → self.registrations[nil] errors)
  handlers = {
    ['client/registerCapability'] = function(_, params, ctx)
      local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
      local valid_regs = vim.tbl_filter(function(reg)
        local cap = vim.lsp.protocol._request_name_to_server_capability[reg.method]
        return cap ~= nil
      end, params.registrations)
      if #valid_regs > 0 then
        client:_register(valid_regs)
        for bufnr in pairs(client.attached_buffers) do
          vim.lsp._set_defaults(client, bufnr)
        end
      end
      return vim.NIL
    end,
  },
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
