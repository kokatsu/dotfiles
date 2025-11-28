-- https://github.com/folke/lazydev.nvim

return {
  'folke/lazydev.nvim',
  ft = 'lua',
  dependencies = {
    -- https://github.com/gonstoll/wezterm-types
    { 'gonstoll/wezterm-types', lazy = true },
  },
  opts = {
    library = {
      { path = 'wezterm-types', mods = { 'wezterm' } },
    },
  },
}
