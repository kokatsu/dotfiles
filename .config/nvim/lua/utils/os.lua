local M = {}

function M.detect_os()
  if vim.fn.has('mac') == 1 then
    return 'mac'
  elseif vim.fn.has('wsl') == 1 then
    return 'wsl'
  elseif vim.fn.has('unix') == 1 then
    return 'linux'
  elseif vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    return 'windows'
  else
    return 'unknown'
  end
end

return M
