---@type vim.lsp.Config
return {
  capabilities = {
    general = {
      -- Use UTF-16 position encoding to match copilot and avoid checkhealth warnings
      positionEncodings = { 'utf-16' },
    },
  },
}
