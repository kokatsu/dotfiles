-- OpenAPI/Swagger preview via redocly (npm-free replacement for swagger-preview.nvim)

local job_id = nil

local function find_port(base)
  for i = 0, 9 do
    local s = vim.uv.new_tcp()
    if s then
      local ok = pcall(s.bind, s, '127.0.0.1', base + i)
      s:close()
      if ok then
        return base + i
      end
    end
  end
  return base
end

local function start()
  if job_id then
    vim.notify('Redocly preview already running', vim.log.levels.WARN)
    return
  end
  local file = vim.fn.expand('%:p')
  local port = find_port(8823) -- https://open.spotify.com/intl-ja/track/3Un4DTzaw3l3BH31tLdrKl
  job_id = vim.fn.jobstart({ 'redocly', 'preview-docs', file, '--port', tostring(port) }, {
    on_exit = function()
      job_id = nil
    end,
  })
  vim.notify(string.format('Redocly preview: http://localhost:%d', port))
end

local function stop()
  if job_id then
    vim.fn.jobstop(job_id)
    job_id = nil
    vim.notify('Redocly preview stopped')
  end
end

local function toggle()
  if job_id then
    stop()
  else
    start()
  end
end

vim.api.nvim_create_user_command('SwaggerPreview', start, {})
vim.api.nvim_create_user_command('SwaggerPreviewStop', stop, {})
vim.api.nvim_create_user_command('SwaggerPreviewToggle', toggle, {})

return {}
