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
    -- Tree-sitter: パーサーとクエリを自動インストール。
    -- moonbit は nvim-treesitter(main) レジストリ未収録だが、プラグインが
    -- install 時の `User TSUpdate` で moonbitlang/tree-sitter-moonbit を登録し、
    -- install が branch=main を ref にビルド + grammar repo の queries/*.scm も
    -- 取り込むため、main ブランチでもハイライト/折りたたみ/インデントが効く。
    treesitter = {
      enabled = true,
      auto_install = true,
    },
    -- LSP: Nix 導入済みの moonbit-lsp を PATH 経由で起動 (vim.lsp.config + enable)。
    -- 注意: lsp は必ずテーブルで渡す。lsp = true はプラグイン内部で boolean を
    -- index してクラッシュする (lsp = false なら無効化)。
    -- native = true にすると moonbit-lsp(Node) でなく moon-lsp(native) --stdio を使う。
    lsp = {},
    -- jsonls (moon.mod.json/moon.pkg.json のスキーマ) と mooncakes (依存補完) は
    -- デフォルト有効のまま使用。
  },
}
