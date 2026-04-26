-- https://github.com/mrcjkb/rustaceanvim

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'rust',
  callback = function(args)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = args.buf, silent = true, desc = desc })
    end
    map('<leader>lr', '<cmd>RustLsp runnables<cr>', 'Runnables')
    map('<leader>lt', '<cmd>RustLsp testables<cr>', 'Testables')
    map('<leader>lD', '<cmd>RustLsp debuggables<cr>', 'Debuggables')
    map('<leader>le', '<cmd>RustLsp expandMacro<cr>', 'Expand macro')
    map('<leader>lc', '<cmd>RustLsp openCargo<cr>', 'Open Cargo.toml')
    map('<leader>lp', '<cmd>RustLsp parentModule<cr>', 'Parent module')
    map('<leader>lE', '<cmd>RustLsp explainError<cr>', 'Explain error')
    map('<leader>lh', '<cmd>RustLsp hover actions<cr>', 'Hover actions')
  end,
})

return {
  'mrcjkb/rustaceanvim',
  version = '^8',
  lazy = false, -- This plugin is already lazy
}
