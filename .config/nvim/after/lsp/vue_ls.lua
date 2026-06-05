-- Vue 3 プロジェクト用。最新 vue-language-server。
-- Vue 2 プロジェクトは vue_ls_legacy が担当するため、ここでは attach しない。
-- on_init/init_options/settings は lua/lsp/vue_shared.lua を参照。
local vue = require('lsp.vue_shared')

---@type vim.lsp.Config
local vue_ls_config = {
  -- overlay で追加した最新版 (Vue 3 専用) を使う
  cmd = { 'vue-language-server-latest', '--stdio' },
  on_init = vue.on_init,
  init_options = vue.init_options,
  settings = vue.settings,
  -- Vue 2 以外（Vue 3 / 判定不能）でのみ attach
  root_dir = vue.make_root_dir(function(major)
    return major ~= 2
  end),
}

return vue_ls_config
