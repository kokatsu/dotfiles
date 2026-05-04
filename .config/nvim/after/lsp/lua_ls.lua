-- https://zenn.dev/uga_rosa/articles/afe384341fc2e1

---@type vim.lsp.Config
return {
  settings = {
    Lua = {
      hint = {
        enable = true,
      },
      runtime = {
        version = 'LuaJIT',
        pathStrict = true,
        path = {
          '?/.lua',
          '?/init.lua',
        },
      },
      workspace = {
        -- workspace.library は lazydev.nvim が動的に管理する
        checkThirdParty = 'Disable',
      },
      telemetry = {
        enable = false,
      },
    },
  },
}
