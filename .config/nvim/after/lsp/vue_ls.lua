---@type vim.lsp.Config
local vue_ls_config = {
  root_markers = { { 'vue.config.js', 'vue.config.ts', 'nuxt.config.js', 'nuxt.config.ts', 'package.json' } },
  settings = {
    vue = {
      suggest = {
        componentNameCasing = 'preferKebabCase',
        propNameCasing = 'preferCamelCase',
      },
      inlayHints = {
        missingProps = true,
        inlineHandlerLeading = true,
        optionsWrapper = true,
        vBindShorthand = true,
      },
    },
  },
}

return vue_ls_config
