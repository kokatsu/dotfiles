{config, ...}: let
  flavor = config.catppuccin.flavor;
  p = config.catppuccinLib.palettes.${flavor};
  names = config.catppuccinLib.flavorNames flavor;
in {
  # herdr: 組み込みテーマは catppuccin-mocha/catppuccin-latte 等のフレーバー別名で
  # 用意されている (--default-config のコメントには載っていないが実機で受理を確認済み)。
  # Ghostty と同じく catppuccin.flavor から導出する。accent はアクティブペイン枠色を
  # 担うキー (ui.accent)。他ツールと同じ blue で揃える
  #
  # [[keys.command]] は tmux の Alt+v/c/g/h ポップアップの herdr 移植版
  # (.config/herdr/scripts/*.sh)。tmux 版と違い bind 時点での条件分岐が
  # できないため claude/codex 判定はスクリプト内で実行時に行う。
  #
  # [ui.toast] は Claude Code Stop/Notification hook の通知 (tmux DCS
  # passthrough 依存、herdr 配下では機能しない) の代わりに herdr ネイティブの
  # 通知機構を使うためのもの。
  #
  # [keys] は herdr を macOS の常用マルチプレクサとした再構築 (WezTerm は
  # タブ/ペイン管理を全撤去した薄い GUI シェル) に合わせた配置:
  # - prefix+t 新タブは旧 WezTerm (ctrl+t) の筋肉記憶
  # - alt+矢印 focus_pane は tmux/WezTerm 時代の direct キーを踏襲
  #   (WezTerm 側の OPT+矢印 SendString と Alt 系バインドは撤去済みが前提)
  # - alt+1..9 focus_agent は左右どちらの Option でも可
  #   (mac.lua で send_composed_key_* = false)
  # 明示していないキーは herdr デフォルト (split_vertical=prefix+v,
  # split_horizontal=prefix+minus, settings=prefix+s, zoom=prefix+z,
  # close_pane=prefix+x, switch_tab=prefix+1..9, workspace_picker=prefix+w,
  # new_worktree=prefix+shift+g, edit_scrollback=prefix+e,
  # open_notification_target=prefix+o 等) を継承。
  #
  # [experimental] は日本語 IME 対策: prefix モード中の ASCII 入力ソース切替と、
  # Claude Code/codex ペインでの IME 候補窓追従。
  home.file = {
    ".config/herdr/config.toml".text = let
      scriptsDir = "${config.xdg.configHome}/herdr/scripts";
    in ''
      [theme]
      name = "${names.kebab}"

      [ui]
      accent = "${p.blue.hex}"
      show_agent_labels_on_pane_borders = true

      [ui.toast]
      delivery = "terminal"

      [keys]
      prefix = "ctrl+space"
      new_tab = "prefix+t"
      focus_pane_left = "alt+left"
      focus_pane_down = "alt+down"
      focus_pane_up = "alt+up"
      focus_pane_right = "alt+right"
      last_pane = "prefix+space"
      focus_agent = "alt+1..9"
      previous_workspace = "prefix+comma"
      next_workspace = "prefix+period"

      [experimental]
      switch_ascii_input_source_in_prefix = true
      reveal_hidden_cursor_for_cjk_ime = true
      cjk_ime_agents = ["claude", "codex"]

      [[keys.command]]
      key = "alt+v"
      type = "pane"
      command = "${scriptsDir}/prompt-edit.sh"
      description = "Claude Code: プロンプト編集"

      [[keys.command]]
      key = "alt+c"
      type = "pane"
      command = "${scriptsDir}/path-pick-fzf.sh"
      description = "パス選択 (fzf)"

      [[keys.command]]
      key = "alt+g"
      type = "pane"
      command = "${scriptsDir}/path-pick-broot.sh"
      description = "パス選択 (broot)"

      [[keys.command]]
      key = "alt+h"
      type = "pane"
      command = "${scriptsDir}/octorus-history.sh"
      description = "Octorus Rally 履歴"

      # alt+y は WSL では WezTerm windows_specific (PowerShell タブ) が先に
      # 捕捉するため macOS 専用
      [[keys.command]]
      key = "alt+y"
      type = "pane"
      command = "${scriptsDir}/yazi-pane.sh"
      description = "Yazi"

      # alt+l は nvim mini.move (<M-l>) を奪うため prefix 側に置く
      [[keys.command]]
      key = "prefix+l"
      type = "pane"
      command = "${scriptsDir}/lazygit-pane.sh"
      description = "Lazygit"

      # 旧 WezTerm Alt+r の移植。feed-watch のデータ生成 (systemd timer) が
      # WSL 限定のため実質 WSL 専用 (macOS ではデータなしメッセージのみ)
      [[keys.command]]
      key = "alt+r"
      type = "pane"
      command = "${scriptsDir}/feed-open.sh"
      description = "未読フィードを開く"
    '';
    ".config/herdr/scripts/prompt-edit.sh" = {
      source = ../../../.config/herdr/scripts/prompt-edit.sh;
      executable = true;
    };
    ".config/herdr/scripts/path-pick-fzf.sh" = {
      source = ../../../.config/herdr/scripts/path-pick-fzf.sh;
      executable = true;
    };
    ".config/herdr/scripts/path-pick-broot.sh" = {
      source = ../../../.config/herdr/scripts/path-pick-broot.sh;
      executable = true;
    };
    ".config/herdr/scripts/octorus-history.sh" = {
      source = ../../../.config/herdr/scripts/octorus-history.sh;
      executable = true;
    };
    ".config/herdr/scripts/yazi-pane.sh" = {
      source = ../../../.config/herdr/scripts/yazi-pane.sh;
      executable = true;
    };
    ".config/herdr/scripts/lazygit-pane.sh" = {
      source = ../../../.config/herdr/scripts/lazygit-pane.sh;
      executable = true;
    };
    ".config/herdr/scripts/feed-open.sh" = {
      source = ../../../.config/herdr/scripts/feed-open.sh;
      executable = true;
    };
  };
}
