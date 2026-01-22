-- https://github.com/catppuccin/nvim

return {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  config = function()
    require('catppuccin').setup({
      flavour = 'mocha', -- latte, frappe, macchiato, mocha
      background = { -- :h background
        light = 'latte',
        dark = 'mocha',
      },
      transparent_background = true, -- enables setting the background color.
      float = {
        transparent = true, -- make floating windows transparent
        solid = false, -- use transparent styling for floating windows, see |winborder|
      },
      show_end_of_buffer = false, -- shows the '~' characters after the end of buffers
      term_colors = false, -- sets terminal colors (e.g. `g:terminal_color_0`)
      dim_inactive = {
        enabled = true, -- dims the background color of inactive window
        shade = 'dark',
        percentage = 0.15, -- percentage of the shade to apply to the inactive window
      },
      no_italic = false, -- Force no italic
      no_bold = false, -- Force no bold
      no_underline = false, -- Force no underline
      styles = { -- Handles the styles of general hi groups (see `:h highlight-args`):
        comments = { 'italic' }, -- Change the style of comments
        conditionals = { 'italic' },
        loops = {},
        functions = {},
        keywords = {},
        strings = {},
        variables = {},
        numbers = {},
        booleans = {},
        properties = {},
        types = {},
        operators = {},
        -- miscs = {}, -- Uncomment to turn off hard-coded styles
      },
      color_overrides = {},
      -- Override specific highlight groups for floating UI
      custom_highlights = function(colors)
        return {
          -- Floating windows (transparent)
          NormalFloat = { bg = 'NONE' },
          FloatBorder = { fg = colors.surface2, bg = 'NONE' },
          FloatTitle = { fg = colors.text, bg = 'NONE', style = { 'bold' } },

          -- Popup menu (completion menu)
          Pmenu = { bg = colors.mantle },
          PmenuSel = { bg = colors.surface0 },
        }
      end,
      default_integrations = true,
      integrations = {
        barbar = true,
        blink_cmp = {
          style = 'bordered',
        },
        fidget = true,
        lsp_styles = {
          enabled = true,
          virtual_text = {
            errors = { 'italic' },
            hints = { 'italic' },
            warnings = { 'italic' },
            information = { 'italic' },
            ok = { 'italic' },
          },
          underlines = {
            errors = { 'underline' },
            hints = { 'underline' },
            warnings = { 'underline' },
            information = { 'underline' },
            ok = { 'underline' },
          },
          inlay_hints = {
            background = true,
          },
        },
        snacks = {
          enabled = true,
          indent_scope_color = 'lavender',
        },
        which_key = true,
      },
    })
    -- setup must be called before loading
    vim.cmd.colorscheme('catppuccin')
  end,
}
