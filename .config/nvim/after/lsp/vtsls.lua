local vue_language_server_path =
  vim.fn.expand('$HOME/.local/share/mise/installs/npm-vue-language-server/3.0.8/lib/node_modules/@vue/language-server')

local vue_plugin = {
  name = '@vue/typescript-plugin',
  location = vue_language_server_path,
  languages = { 'vue' },
  configNamespace = 'typescript',
}

local tsserver_filetypes = {
  'vue',
  'svelte',
}

---@type vim.lsp.Config
local vtsls_config = {
  workspace_required = true,
  root_dir = function(bufnr, on_dir)
    local root_markers = { 'package.json', 'tsconfig.json', 'jsconfig.json' }
    local project_root = vim.fs.root(bufnr, root_markers)
    on_dir(project_root)
  end,
  settings = {
    vtsls = {
      tsserver = {
        globalPlugins = {
          vue_plugin,
        },
      },
    },
  },
  filetypes = tsserver_filetypes,
}

return vtsls_config
