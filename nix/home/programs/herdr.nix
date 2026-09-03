{
  config,
  inputs,
  lib,
  pkgs,
  validDotfilesDir,
  ...
}: let
  flavor = config.catppuccin.flavor;
  p = config.catppuccinLib.palettes.${flavor};
  names = config.catppuccinLib.flavorNames flavor;

  # .config/herdr/scripts/*.sh を列挙して home.file エントリを生成する。
  # スクリプトを足すたびにこのファイルへ 1 件ずつ書き足す手間をなくすため。
  # regular file のみ拾うのでサブディレクトリは対象外
  scriptsSrc = ../../../.config/herdr/scripts;
  scriptEntries =
    lib.mapAttrs' (name: _:
      lib.nameValuePair ".config/herdr/scripts/${name}" {
        source = scriptsSrc + "/${name}";
        executable = true;
      })
    (lib.filterAttrs
      (name: type: type == "regular" && lib.hasSuffix ".sh" name)
      (builtins.readDir scriptsSrc));
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
  # - alt+shift+矢印 move_tab_* (0.8.2 で追加) はタブの並べ替え。alt+矢印 と
  #   違い WezTerm 側に元から binding がないため無効化不要
  # 明示していないキーは herdr デフォルト (split_vertical=prefix+v,
  # split_horizontal=prefix+minus, settings=prefix+s, zoom=prefix+z,
  # switch_tab=prefix+1..9, workspace_picker=prefix+w,
  # new_worktree=prefix+shift+g, edit_scrollback=prefix+e,
  # open_notification_target=prefix+o 等) を継承。
  #
  # [experimental] は日本語 IME 対策: prefix モード中の ASCII 入力ソース切替と、
  # Claude Code/codex ペインでの IME 候補窓追従。
  home.file =
    {
      ".config/herdr/config.toml".text = let
        scriptsDir = "${config.xdg.configHome}/herdr/scripts";
      in ''
        onboarding = false

        [theme]
        name = "${names.kebab}"

        [ui]
        accent = "${p.blue.hex}"
        show_agent_labels_on_pane_borders = true
        # デフォルトの "{hostname}: {workspace}" だと WezTerm 側のタブタイトル
        # (format.lua が表示幅で省略) が長いホスト名だけで埋まり実質固定表示に
        # なるため workspace/tab に差し替える
        window_title = "{workspace}: {tab}"
        # tab-numbers プラグインが付ける [N] プレフィックスの分を確保する
        # (デフォルト 26)
        sidebar_width = 30

        [ui.sidebar.agents]
        row_gap = 1

        # Claude Code は OSC タイトルにセッション要約を書き、Codex は
        # tui.terminal_title の thread にセッション名を書くので、その行を
        # デフォルトレイアウトに挟んで表示する。override は rows を丸ごと
        # 置き換えるため全行を明示
        [ui.sidebar.agents.rows_by_agent]
        # $wsnum はカスタムトークンのデフォルト (overlay0 + dim) だと薄すぎるので、
        # ワークスペース名の非アクティブ時スタイル (subtext0 + bold) に合わせる
        claude = [
          ["state_icon", { token = "$wsnum", fg = "${p.subtext0.hex}", bold = true, dim = false }, "workspace", { token = "tab", fg = "${p.yellow.hex}", bold = true }],
          # $cache は herdr-cache-token.ts が報告する prompt cache の失効時刻。
          # --ttl-ms で失効と同時に消えるため、無表示 = キャッシュ切れを意味する
          ["agent", "$cache"],
          ["terminal_title_stripped"],
        ]
        codex = [
          ["state_icon", { token = "$wsnum", fg = "${p.subtext0.hex}", bold = true, dim = false }, "workspace", { token = "tab", fg = "${p.yellow.hex}", bold = true }],
          ["agent"],
          ["terminal_title_stripped"],
        ]

        [ui.sidebar.spaces]
        # tab-numbers プラグインが報告する $number トークンで番号を表示する
        # (デフォルト行構成に $number を挿し込んだもの)
        rows = [["state_icon", "$number", "workspace"], ["branch", "git_status"]]
        row_gap = 1

        [ui.toast]
        delivery = "${
          if pkgs.stdenv.hostPlatform.isLinux
          then "herdr"
          else "terminal"
        }"

        [ui.toast.herdr]
        position = "bottom-right"

        [ui.sound]
        enabled = ${lib.boolToString pkgs.stdenv.hostPlatform.isLinux}

        [keys]
        prefix = "ctrl+space"
        # デタッチは押し間違えると作業中のセッションから抜けてしまうので shift 必須にする
        detach = "prefix+shift+q"
        new_tab = "prefix+t"
        move_tab_previous = "alt+shift+left"
        move_tab_next = "alt+shift+right"
        # prefix+x は close-pane-confirm.sh (custom command) に譲る。
        # 無効化しないとデフォルトの close_pane が勝ち custom command 側が捨てられる
        close_pane = ""
        focus_pane_left = "alt+left"
        focus_pane_down = "alt+down"
        focus_pane_up = "alt+up"
        focus_pane_right = "alt+right"
        last_pane = "prefix+space"
        focus_agent = "alt+1..9"
        previous_workspace = "prefix+comma"
        next_workspace = "prefix+period"
        # デフォルトの prefix+b を下の custom command に譲り、使用頻度の低い
        # サイドバー切替を別キーへ移す
        toggle_sidebar = "prefix+shift+b"

        # Herdr の agent list 順で次の blocked エージェントへ移動する。末尾では先頭へ
        # 折り返し、該当エージェントがいなければ通知する
        [[keys.command]]
        key = "prefix+b"
        type = "shell"
        command = "${scriptsDir}/focus-next-blocked-agent.sh"
        description = "次の blocked エージェントへ移動"

        [experimental]
        kitty_graphics = true
        switch_ascii_input_source_in_prefix = true
        reveal_hidden_cursor_for_cjk_ime = true
        cjk_ime_agents = ["claude", "codex"]

        # close_pane の置き換え。エージェントが idle (緑) 以外なら close-confirm
        # プラグインの popup 確認画面を開く (prefix+z 押し間違いによる稼働中
        # エージェントの喪失防止)。popup 型 custom command は即閉じパスでも一瞬
        # 描画されるため、shell 型 + 必要時のみ plugin pane open の構成
        [[keys.command]]
        key = "prefix+x"
        type = "shell"
        command = "${scriptsDir}/close-pane-confirm.sh"
        description = "ペインを閉じる (エージェント稼働中は確認)"

        # 現在のペインを左上として、左右 1:1、左上下 3:1、右上下 1:1 に分割
        [[keys.command]]
        key = "prefix+backslash"
        type = "shell"
        command = "${scriptsDir}/four-pane-layout.sh"
        description = "4ペイン作業レイアウト"

        # 新しいペインを全高の左列として追加し、既存ペインを右列で上下 1:1 に分割する。
        [[keys.command]]
        key = "prefix+left"
        type = "shell"
        command = "${scriptsDir}/three-pane-layout.sh full-left"
        description = "3ペイン作業レイアウト (左を全高)"

        # 既存ペインを左列で上下 1:1 に配置し、新しいペインを全高の右列にする。
        [[keys.command]]
        key = "prefix+right"
        type = "shell"
        command = "${scriptsDir}/three-pane-layout.sh full-right"
        description = "3ペイン作業レイアウト (右を全高)"

        # 選択中のペインを指定方向の隣接ペインと入れ替える。
        [[keys.command]]
        key = "prefix+shift+left"
        type = "shell"
        command = "${scriptsDir}/swap-pane.sh left"
        description = "ペインを左と入れ替え"

        [[keys.command]]
        key = "prefix+shift+down"
        type = "shell"
        command = "${scriptsDir}/swap-pane.sh down"
        description = "ペインを下と入れ替え"

        [[keys.command]]
        key = "prefix+shift+up"
        type = "shell"
        command = "${scriptsDir}/swap-pane.sh up"
        description = "ペインを上と入れ替え"

        [[keys.command]]
        key = "prefix+shift+right"
        type = "shell"
        command = "${scriptsDir}/swap-pane.sh right"
        description = "ペインを右と入れ替え"

        # tmux の break-pane (prefix+!) と同じく、現在のペインを新しいタブへ移動
        [[keys.command]]
        key = "prefix+!"
        type = "shell"
        command = "${scriptsDir}/move-pane-to-new-tab.sh"
        description = "現在のペインを新しいタブへ移動"

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

        # ステータスバーのアイコンは色でしか状態を示さないので、詳細を見る動線を
        # キーに割り当てる。fzf を挟まないので type は shell (pane だと一時的な
        # 分割が開くだけ無駄になる)。alt+s は WezTerm 側の SSH タブが取っている
        [[keys.command]]
        key = "alt+i"
        type = "shell"
        command = "${scriptsDir}/status-open.sh"
        description = "異常のあるサービスの Statuspage を開く"
      '';
      # Claude Code / Codex の SessionStart から呼ぶ agent session 報告フック。
      # `herdr integration install` が生成していた埋め込み Python のスクリプト
      # 2 本 (上流の更新で上書きされる生成物) を自前の 1 本に置き換えたもの。
      # 両エージェントで共有するため、配置はこのファイルだけが持つ
      # (claude-code.nix / codex.nix 側では扱わない)
      ".config/herdr/hooks/report-agent-session.sh" = {
        source = ../../../.config/herdr/hooks/report-agent-session.sh;
        executable = true;
      };
      ".config/herdr/hooks/report-agent-session.ts".source = ../../../.config/herdr/hooks/report-agent-session.ts;

      # .config/herdr/plugins/close-confirm は home.file で配置しない:
      # plugin link が symlink を解決して plugin_root が /nix/store になり、
      # rebuild のたびに store パスが変わって登録が陳腐化するため。
      # リポジトリの実パスの登録は下の linkHerdrPlugins が行う
    }
    // scriptEntries;

  # plugin link は plugins.json を直接書くだけでサーバ起動を必要とせず、
  # 登録済み ID の再 link も冪等 (キャッシュされた manifest が更新されるため
  # herdr-plugin.toml 編集後の再登録を兼ねる)。いずれも 0.8.0 で確認済み。
  # ただし disable 済みのプラグインは再 link で enabled に戻るので、手で
  # 無効化して使う運用に変えるならその行を外すこと。
  #
  # tab-numbers は kokatsu/herdr-tab-numbers に切り出したので flake input の
  # store パスを登録する。pin を変えたときだけパスが変わるため陳腐化しない。
  # close-confirm は close-pane-confirm.sh と対でこのリポジトリに残しているため、
  # 従来どおりチェックアウトの実パスを登録する
  home.activation.linkHerdrPlugins = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr plugin link \
      "${validDotfilesDir}/.config/herdr/plugins/close-confirm" > /dev/null
    $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr plugin link \
      "${inputs.herdr-tab-numbers}" > /dev/null
  '';
}
