local M = {}

function M.detect_os()
  local os_name
  if vim.fn.has('mac') == 1 then
    os_name = 'mac'
  elseif vim.fn.has('unix') == 1 then
    -- WSLかLinuxかを判定
    local is_wsl = false
    local f = io.open('/proc/version', 'r')
    if f then
      local content = f:read('*all')
      f:close()
      if content:match('Microsoft') or content:match('WSL') then
        is_wsl = true
      end
    end

    if is_wsl then
      os_name = 'wsl'
    else
      os_name = 'linux'
    end
  elseif vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    os_name = 'windows'
  else
    os_name = 'unknown'
  end

  return os_name
end

return M
