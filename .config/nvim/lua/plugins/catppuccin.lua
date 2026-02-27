-- https://github.com/catppuccin/nvim

return {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  opts = {
    flavour = 'mocha',
    background = { light = 'latte', dark = 'mocha' },
    transparent_background = true,
    float = { transparent = true, solid = false },
    dim_inactive = {
      enabled = true,
      shade = 'dark',
      percentage = 0.15,
    },
    styles = {
      comments = { 'italic' },
      conditionals = { 'italic' },
    },
    custom_highlights = function(colors)
      return {
        FloatBorder = { fg = colors.surface2 },
        Pmenu = { bg = colors.mantle },
        PmenuSel = { bg = colors.surface0 },
      }
    end,
    auto_integrations = true,
    integrations = {
      blink_cmp = { style = 'bordered' },
      snacks = { enabled = true, indent_scope_color = 'lavender' },
    },
  },
  config = function(_, opts)
    require('catppuccin').setup(opts)
    vim.cmd.colorscheme('catppuccin')
  end,
}
