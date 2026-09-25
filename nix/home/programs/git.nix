{lib, ...}: {
  # 参考: https://blog.gitbutler.com/how-git-core-devs-configure-git/
  programs.git = {
    enable = true;
    signing.format = null;
    # config.local を先に読み、共通設定が後から上書きする既存の優先順位を維持。
    settings = {
      alias = {
        a = "add";
        aa = "add --all";
        au = "add -u";
        b = "branch --list";
        # https://github.com/sharkdp/bat#git-diff
        bd = "!git diff --name-only --relative --diff-filter=d | xargs bat --diff";
        cm = "commit -m";
        co = "checkout";
        cp = "cherry-pick";
        d = "diff";
        # difftastic 使用時は delta 連携 alias を無効化 (戻す場合はコメント解除)。
        # dd = ''!f() { git diff "$@" | delta --side-by-side --paging=never; }; f'';
        ds = "diff --staged";
        # dsd = ''!f() { git diff --staged "$@" | delta --side-by-side --paging=never; }; f'';
        d1 = "diff HEAD^";
        # d1d = ''!f() { git diff HEAD^ "$@" | delta --side-by-side --paging=never; }; f'';
        f = "fetch origin";
        fd = "!git branch | fzf --preview 'git log -1 --color=always --stat {-1}' --preview-window=right,60% | xargs git checkout";
        l = "log --date=format-local:'%Y/%m/%d %a %H:%M' --pretty=format:'%C(yellow)%h %C(bold blue)(%ad)%C(auto)%d %C(reset)%s %C(bold magenta)<%an>' --graph";
        la = "log --date=format-local:'%Y/%m/%d %a %H:%M' --pretty=format:'%C(yellow)%h %C(bold blue)(%ad)%C(auto)%d %C(reset)%s %C(bold magenta)<%an>' --graph --all --date-order";
        lf = "log --pretty=fuller";
        # Conventional Commit の種類ごとに背景色とアイコンを付ける。
        # https://www.nerdfonts.com/cheat-sheet
        # https://catppuccin.com/palette/
        # feat: nf-md-shimmer rgb(137, 220, 235)
        # fix: nf-md-bug rgb(243, 139, 168)
        # chore: nf-md-broom rgb(203, 166, 247)
        # docs: nf-md-file_document rgb(148, 226, 213)
        # style: nf-md-palette rgb(250, 179, 135)
        # test: nf-md-test_tube rgb(180, 190, 254)
        # refactor: nf-fa-recycle rgb(166, 227, 161)
        # ci: nf-md-rocket_launch rgb(137, 180, 250)
        # build: nf-md-crane rgb(245, 194, 231)
        # perf: nf-fa-bolt rgb(249, 226, 175)
        lg = lib.concatStrings [
          "!f() { "
          "        git log --pretty=format:'%C(yellow)%h %C(bold blue)(%ad)%C(auto)%d %C(reset)%s %C(bold magenta)<%an>' -n 30 --color=always \"$@\" | "
          "        sed -E     "
          "        -e 's/(feat)(\\(.*\\))?:/\\x1b[48;2;137;220;235m\\x1b[30m 󱕅 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(fix)(\\(.*\\))?:/\\x1b[48;2;243;139;168m\\x1b[30m 󰃤 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(chore)(\\(.*\\))?:/\\x1b[48;2;203;166;247m\\x1b[30m 󰃢 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(docs)(\\(.*\\))?:/\\x1b[48;2;148;226;213m\\x1b[30m 󰈙 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(style)(\\(.*\\))?:/\\x1b[48;2;250;179;135m\\x1b[30m 󰏘 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(test)(\\(.*\\))?:/\\x1b[48;2;180;190;254m\\x1b[30m 󰙨 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(refactor)(\\(.*\\))?:/\\x1b[48;2;166;227;161m\\x1b[30m  \\1\\2: \\x1b[0m/'     "
          "        -e 's/(ci)(\\(.*\\))?:/\\x1b[48;2;137;180;250m\\x1b[30m 󱓞 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(build)(\\(.*\\))?:/\\x1b[48;2;245;194;231m\\x1b[30m 󰡢 \\1\\2: \\x1b[0m/'     "
          "        -e 's/(perf)(\\(.*\\))?:/\\x1b[48;2;249;226;175m\\x1b[30m  \\1\\2: \\x1b[0m/' ;     }; f"
        ];
        lh = "log --date=format-local:'%Y/%m/%d %a %H:%M' --pretty=format:'%C(yellow)%H %C(bold blue)(%ad)%C(auto)%d %C(reset)%s %C(bold magenta)<%an>' --graph";
        lm = "!f() { author=$(git config user.name); git log --date=format-local:'%Y/%m/%d %a %H:%M' --pretty=format:'%C(yellow)%h %C(bold blue)(%ad)%C(auto)%d %C(reset)%s' --author=\"$author\" --graph; }; f";
        ls = "log --date=format-local:'%Y/%m/%d %a %H:%M' --pretty=format:'%C(yellow)%h %C(bold blue)(%ad) %C(reset)%C(brightblack)[%cd]%C(auto)%d %C(reset)%s %C(bold magenta)<%an>' --graph";
        l1 = "log -1";
        m = "merge";
        now = "!f() { git commit --amend --no-edit --date=\"$(date -R)\"; git rebase HEAD~1 --committer-date-is-author-date; }; f";
        p = "pull";
        po = "push origin HEAD";
        rb = "rebase";
        rh = "reset --hard";
        rh0 = "reset --hard HEAD";
        rs = "reset --soft";
        rs1 = "reset --soft HEAD^";
        s = "status";
        sw = "switch";
        swc = "switch -c";
        wip = "commit -am 'chore(wip): :construction: work in progress'";
      };
      branch = {
        # ブランチを表示する際、最新のコミット日時順にソートする。
        sort = "-committerdate";
      };
      color = {
        ui = true;
        status = {
          added = "green";
          changed = "yellow";
          untracked = "red";
        };
      };
      column = {
        # git branch や git tag などのコマンド出力を自動的にカラム表示する。
        ui = "auto";
      };
      commit = {
        # コミットメッセージを詳細に表示する。
        verbose = true;
      };
      core = {
        # Git の操作で使用するエディタを Neovim に設定する。
        editor = "nvim";
        # 日本語ファイル名をエスケープせずそのまま表示する。
        quotepath = false;
        # 未追跡ファイルのキャッシュを有効にする。
        untrackedCache = true;
        # デフォルトのページャーを less に設定する場合はコメント解除。
        # pager = "less -+X -+F -+S --quit-if-one-screen -+G --no-init --raw-control-chars -K";
        # difftastic 使用時は delta を無効化 (戻す場合はコメント解除)。
        # pager = "delta";
      };
      # delta = {
      #   features = "catppuccin-mocha";
      #   navigate = true;
      #   dark = true;
      #   pager = "less --quiet";
      # };
      diff = {
        # 外部 diff ツールに difftastic を使用 (構文ベースの構造的 diff)。
        external = "difft";
        # 差分を表示する際、差分アルゴリズムを histogram に設定する。
        algorithm = "histogram";
        # コードの移動を検出し、色付けして表示する。
        colorMoved = "plain";
        # 差分表示のプレフィックスをわかりやすくする。
        mnemonicPrefix = true;
        # 差分表示の際にファイル名の変更を検出する。
        renames = true;
      };
      fetch = {
        # フェッチする時に、不要なブランチを削除する。
        prune = true;
        # フェッチする時に、不要なタグを削除する。
        pruneTags = true;
        # フェッチする時に、すべてのリモートから取得する。
        all = true;
      };
      help = {
        # コマンド名を間違えた場合、補正候補の実行前に確認する。
        autocorrect = "prompt";
      };
      init = {
        # git init 時のデフォルトのブランチ名を main に設定する。
        defaultBranch = "main";
      };
      # difftastic はフィルタ非対応。delta に戻す場合はコメント解除。
      # interactive.diffFilter = "delta";
      # mergiraf.nix が diff3 に固定する。mergiraf をやめる場合はコメント解除。
      # merge = {
      #   # 共通祖先も表示し、両側で一致する行は競合領域の外に出す。
      #   conflictStyle = "zdiff3";
      # };
      pull = {
        # マージではなくリベースする (rebase.autoStash / updateRefs も有効になる)。
        rebase = true;
      };
      push = {
        # 現在のブランチを同名の追跡先ブランチへプッシュする。
        default = "simple";
        # 新しいブランチの初回プッシュ時に追跡先を設定する。
        autoSetupRemote = true;
        # プッシュ時に、関連するタグも一緒にプッシュする。
        followTags = true;
        # --force-with-lease 時に、リモートの更新をローカルへ取り込み済みかも検査する。
        useForceIfIncludes = true;
      };
      rebase = {
        # インタラクティブリベースで fixup! や squash! を自動的に適切な位置へ移す。
        autoSquash = true;
        # 作業中の変更をリベース前に一時的にスタッシュし、終了後に復元する。
        autoStash = true;
        # todo の行が消えていたら停止する (意図的に落とす場合は drop を使う)。
        missingCommitsCheck = "error";
        # リベース時に、関連するブランチの参照も更新する。
        updateRefs = true;
      };
      rerere = {
        # コンフリクトの解消結果を記録し、同じコンフリクトが再発した際に再利用する。
        enabled = true;
        # 再利用した解消結果をインデックスにも反映する。
        autoupdate = true;
      };
      tag = {
        # バージョン番号として降順にソートする (v1.10.0 が v1.9.0 より上にくる)。
        sort = "-version:refname";
      };
      transfer = {
        # URL に平文の認証情報が埋め込まれていた場合、警告ではなく失敗させる。
        credentialsInUrl = "die";
      };
      user = {
        # user.name / user.email を推測せず、設定ファイルに明示された値だけを使う。
        useConfigOnly = true;
      };
    };
    ignores = [
      ".kokatsu"
      ".bookmarks"
      ".local"
      "*.local"
      "*.local.*"
      ".env"
      ".env.*"
      ".DS_Store"
    ];
  };

  xdg.configFile."git/config".text = lib.mkBefore (lib.generators.toGitINI {
    include.path = "./config.local";
  });

  # lazygit の diffRenderers が delta を呼ぶ (git 側は difftastic)。
  programs.delta = {
    enable = true;
    enableGitIntegration = false;
  };
}
