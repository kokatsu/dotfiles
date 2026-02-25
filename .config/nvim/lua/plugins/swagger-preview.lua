-- https://github.com/vinnymeller/swagger-preview.nvim

return {
  'vinnymeller/swagger-preview.nvim',
  cmd = { 'SwaggerPreview', 'SwaggerPreviewStop', 'SwaggerPreviewToggle' },
  build = 'npm i',
  opts = function()
    local port = 8823 -- https://open.spotify.com/intl-ja/track/3Un4DTzaw3l3BH31tLdrKl
    for i = 0, 9 do
      local s = vim.uv.new_tcp()
      if s then
        local ok = pcall(s.bind, s, '127.0.0.1', port + i)
        s:close()
        if ok then
          return { port = port + i, host = 'localhost' }
        end
      end
    end
    return { port = port, host = 'localhost' }
  end,
}
