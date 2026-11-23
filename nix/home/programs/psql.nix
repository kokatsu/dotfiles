{
  pkgs,
  config,
  ...
}: {
  # psql は HISTFILE の親ディレクトリを作らず、無ければ履歴を黙って捨てる
  xdg.stateFile."psql/.keep".text = "";

  xdg.configFile."pg".source =
    pkgs.writeTextDir ".psqlrc"
    # sql
    ''
      -- ---------- テーブル出力の設定 ----------

      -- 罫線を内側のみ表示 (0=なし, 2=外枠も)
      \pset border 1
      \pset linestyle unicode
      \pset null '[NULL]'
      \pset pager off

      -- ---------- 入力補完・履歴の設定 ----------

      -- タブ補完で挿入するキーワードを大文字にする
      \set COMP_KEYWORD_CASE upper
      -- 直前と同じコマンドを履歴に残さない
      \set HISTCONTROL ignoredups
      -- 履歴ファイルを接続データベースごとに分ける
      \set HISTFILE ${config.xdg.stateHome}/psql/history- :DBNAME
      \set HISTSIZE 10000

      -- ---------- プロンプトの設定 ----------

      -- 通常プロンプト (カレントDBと時刻を緑で表示)
      \set PROMPT1 '%[%033[1;32m%]%/ [%`date +%H:%M:%S`] %R%#%[%033[0m%] '
      -- 継続行のプロンプト
      \set PROMPT2 '[more] %R > '

      -- ---------- その他の設定 ----------

      \set VERBOSITY verbose
      \timing
      -- 行が広いとき自動で拡張表示に切り替え
      \x auto
    '';
}
