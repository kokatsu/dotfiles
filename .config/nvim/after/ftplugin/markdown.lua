-- Toggle markdown checkbox: - [ ] <-> - [x]
local function toggle_checkbox()
  local line = vim.api.nvim_get_current_line()
  if line:match('%- %[x%]') then
    line = line:gsub('%- %[x%]', '- [ ]', 1)
  elseif line:match('%- %[ %]') then
    line = line:gsub('%- %[ %]', '- [x]', 1)
  else
    return
  end
  vim.api.nvim_set_current_line(line)
end

vim.keymap.set('n', '<leader>x', toggle_checkbox, { buffer = true, desc = 'Toggle checkbox' })
