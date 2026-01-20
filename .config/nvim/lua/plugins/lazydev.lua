-- https://github.com/folke/lazydev.nvim

return {
  'folke/lazydev.nvim',
  ft = 'lua',
  dependencies = {
    -- https://github.com/justinsgithub/wezterm-types
    { 'justinsgithub/wezterm-types', lazy = true },
  },
  opts = {
    library = {
      { path = 'wezterm-types', mods = { 'wezterm' } },
    },
  },
}
