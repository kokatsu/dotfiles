-- https://github.com/mrcjkb/rustaceanvim

return {
  'mrcjkb/rustaceanvim',
  version = '^7',
  lazy = false, -- This plugin is already lazy
  init = function()
    vim.g.rustaceanvim = {
      server = {
        capabilities = {
          general = {
            -- Use UTF-16 position encoding to match copilot and avoid checkhealth warnings
            positionEncodings = { 'utf-16' },
          },
        },
      },
    }
  end,
}
