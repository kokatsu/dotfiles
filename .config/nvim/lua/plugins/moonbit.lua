-- https://github.com/moonbit-community/moonbit.nvim

return {
  'moonbit-community/moonbit.nvim',
  -- ft 指定で lazy が起動時に同梱 ftdetect (.mbt/.mbti/moon.pkg → moonbit) を
  -- 先にソースするため、初回ファイルオープンでも filetype 検出 → ロードが成立する
  ft = 'moonbit',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  opts = {
    treesitter = {
      enabled = true,
      auto_install = false,
    },
    -- LSP: Nix 導入済みの moon-lsp(native) --stdio を PATH 経由で起動 (vim.lsp.config + enable)。
    -- 注意: lsp は必ずテーブルで渡す。lsp = true はプラグイン内部で boolean を
    -- index してクラッシュする (lsp = false なら無効化)。
    -- native = false は Node 版 moonbit-lsp を使うが、Nix のツールチェーンには含まれない。
    lsp = {},
    -- jsonls (moon.mod.json/moon.pkg.json のスキーマ) と mooncakes (依存補完) は
    -- デフォルト有効のまま使用。
  },
}
