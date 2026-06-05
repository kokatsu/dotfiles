-- Vue 2 プロジェクト用。Vue 2 をサポートする最後の系列 3.0.x に固定した
-- vue-language-server (overlay pin, PATH 既定)。
-- vue_ls (最新) と同じ v3 系プロトコルなので共有設定をそのまま流用する。
-- nvim-lspconfig には vue_ls_legacy の定義が無いため filetypes も明示する。
local vue = require('lsp.vue_shared')

---@type vim.lsp.Config
local vue_ls_legacy_config = {
  filetypes = { 'vue' },
  -- PATH 既定の 3.0.x (overlay で pin)
  cmd = { 'vue-language-server', '--stdio' },
  on_init = vue.on_init,
  init_options = vue.init_options,
  settings = vue.settings,
  -- Vue 2 プロジェクトでのみ attach
  root_dir = vue.make_root_dir(function(major)
    return major == 2
  end),
}

return vue_ls_legacy_config
