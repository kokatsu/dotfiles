---@type vim.lsp.Config
return {
  filetypes = { 'markdown' },
  -- markdown-oxide は vault root 配下の隠しディレクトリを走査しないため、`.kokatsu/`
  -- のノートは root がリポジトリのままだとインデックスされない。`.moxide.toml` を
  -- `.git` より高い優先度グループに置くことで、`.moxide.toml` を持つ `.kokatsu/` は
  -- それ自体が vault root になる。marker を持たないリポジトリの挙動は変わらない。
  root_markers = { { '.moxide.toml', '.obsidian' }, '.git' },
}
