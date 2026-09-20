_: {
  programs.broot = {
    enable = true;
    settings = {
      # Yazi 風操作感: hjkl 移動 + 単一キーショートカット有効化
      # 検索は `/` で開始 (Space は staging 切替に上書き)
      modal = true;
      initial_mode = "command";

      # デフォルトで hidden ファイル (-h)、git-ignored ファイル (-i) を表示し、
      # ディレクトリをファイルより上に並べる (Yazi の sort_dir_first 相当)
      default_flags = "-hi --sort-by-type-dirs-first";

      # アイコン表示 (Nerd Font をターミナルに設定済みであること)
      icon_theme = "nerdfont";

      # catppuccin/nix が公式 skin を後から import して丸ごと上書きするため、
      # ここには skin を定義せず flavor / accent の追従を一元化する。

      verbs = [
        # Ctrl+p: カレント選択 (ファイル/ディレクトリ両対応) を
        # $CLAUDE_PATH_PICK_FILE に書き出して broot を終了
        # Claude Code / Codex CLI のパス選択スクリプト
        # (.config/herdr/scripts/path-pick-broot.sh) から利用
        # 変数名は Claude 由来だが、Codex 側スクリプトでも同じ受け渡しに使う
        {
          invocation = "pp";
          key = "ctrl-p";
          execution = "printf '%s' {file} > $CLAUDE_PATH_PICK_FILE";
          from_shell = true;
          leave_broot = true;
        }
        # デフォルトの Enter (ファイル上) は :open_stay を発動し、WSL では
        # Windows の「ファイルを開く」ダイアログが出るため、同じリダイレクトに置き換える
        # (ディレクトリ上の Enter はデフォルトの :focus のままで階層移動可能)
        {
          key = "enter";
          execution = "printf '%s' {file} > $CLAUDE_PATH_PICK_FILE";
          from_shell = true;
          apply_to = "file";
          leave_broot = true;
        }
        # Space: staging 切替 (Yazi 風複数選択)
        # modal モードの Space (input mode 切替) を上書きする。検索は `/` で開始する
        {
          key = "space";
          execution = ":toggle_stage";
        }
        # Ctrl+a: staged したパスを改行区切りでまとめて送信 (複数選択の確定)
        {
          key = "ctrl-a";
          execution = "printf '%s' {file:new-line-separated} > $CLAUDE_PATH_PICK_FILE";
          from_shell = true;
          leave_broot = true;
        }
      ];
    };
  };
}
