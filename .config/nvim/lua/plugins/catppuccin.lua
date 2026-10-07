-- https://github.com/catppuccin/nvim

local palette = require('utils.palette')
local flavour = palette.flavor()
local light_flavour = palette.light_flavor()

return {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  opts = {
    flavour = flavour,
    background = { light = light_flavour, dark = flavour },
    transparent_background = true,
    float = { transparent = true, solid = false },
    styles = {
      comments = { 'italic' },
      conditionals = { 'italic' },
    },
    custom_highlights = function(colors)
      local U = require('catppuccin.utils.colors')
      return {
        -- 非アクティブな分割ウィンドウの背景 (autocmds.lua が winhighlight で割り当てる)。
        -- dim_inactive の shade = 'light', percentage = 0.6 と同じ式
        DimInactive = {
          fg = colors.text,
          bg = U.vary_color(
            { latte = U.lighten('#FBFCFD', 0.6, colors.base) },
            U.lighten(colors.surface0, 0.6, colors.base)
          ),
        },
        FloatBorder = { fg = colors.surface2 },
        Pmenu = { bg = colors.mantle },
        PmenuSel = { bg = colors.surface0 },
        -- Window 分割の境界線 / 行番号 (flavor に追従)
        WinSeparator = { fg = colors.overlay0, bg = 'NONE' },
        LineNr = { fg = colors.overlay0, bg = 'NONE' },
        -- Markdown のインラインコード (after/lsp/kakehashi.lua の captureMappings)
        ['@lsp.typemod.string.documentation.markdown'] = { fg = colors.subtext0, bg = colors.surface0 },
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
