---@type vim.lsp.Config
local serve_d_config = {
  -- dub プロジェクトなら dub.json/dub.sdl のあるディレクトリを root に、
  -- なければファイル自身のディレクトリを root にして単発 .d ファイルでも起動させる。
  -- (デフォルトの `.git` 検出は非 D プロジェクト全体を掴んでしまうため使わない)
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local root = vim.fs.root(fname, { 'dub.json', 'dub.sdl' })
    on_dir(root or vim.fs.dirname(fname))
  end,
  settings = {
    dfmt = {
      braceStyle = 'stroustrup',
    },
  },
}

return serve_d_config
