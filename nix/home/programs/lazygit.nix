{
  lib,
  config,
  isWSL,
  ...
}: {
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        showRandomTip = false;
        showBottomLine = false;
        showCommandLog = false;
        scrollHeight = 10;
        expandFocusedSidePanel = true;
        nerdFontsVersion = "3";
        showNumstatInFilesView = true;
        showDivergenceFromBaseBranch = "arrowAndNumber";
        filterMode = "fuzzy";
        skipNoStagedFilesWarning = true;
        # 既定は "02 Jan 06" / "3:04PM" (12時間表記)
        timeFormat = "2006-01-02";
        shortTimeFormat = "15:04";
        # 色名はターミナルパレット (= catppuccin) を参照するため flavor 追従する
        branchColorPatterns = {
          "^main$" = "green";
          "^[0-9]{8}$" = "blue";
          "^renovate/" = "yellow";
        };
        # theme は catppuccin/nix で管理
      };
      git = {
        # `|` で循環切り替えできる。staging view は常に plain diff (--no-ext-diff)
        # で取得されるため、difftastic を選んでも行/ハンク単位のステージは壊れない
        diffRenderers = [
          # git config の diff.external = difft を流用 (.gitattributes でファイル型別設定も可)
          {
            name = "difftastic";
            type = "extDiff";
          }
          {
            name = "delta";
            command = "delta --dark --paging=never";
          }
          # pager なしの素の git diff
          {
            name = "plain";
            type = "rawGit";
          }
        ];
      };
      os =
        {
          editPreset = "nvim-remote";
          # lazygit は $SHELL -c でコマンドを実行するため、`:` プロンプトと
          # customCommands から zsh の関数を呼べるようにする
          shellFunctionsFile = "${config.xdg.configHome}/zsh/functions.zsh";
        }
        // lib.optionalAttrs isWSL {
          # 本物の clip.exe は UTF-8 を CP932 扱いして文字化けさせるため使わない。
          # win32yank.exe は UTF-8 を扱えるが Windows プロセスの起動に実測 462ms かかる。
          # WSLg が X クリップボードと Windows クリップボードを双方向同期するので、
          # xsel (実測 9ms) でも同じ宛先に UTF-8 のまま届く。
          copyToClipboardCmd = "printf '%s' {{text}} | xsel -ib";
          # lazygit は copyToClipboardCmd の有無で貼り付け側も分岐する。
          # 未設定だと空コマンドを実行してしまうため対で必要
          readFromClipboardCmd = "xsel -ob";
          # lazygit の WSL 既定値は powershell.exe を使うが PATH 上に無いため wslview へ
          open = "wslview {{filename}} >/dev/null";
          openLink = "wslview {{link}} >/dev/null";
        };
      # Nix 管理のため自己更新は不可能
      update.method = "never";
      disableStartupPopups = true;
      notARepository = "skip";
      promptToReturnFromSubprocess = false;
      customCommands = [
        {
          key = "F";
          context = "files";
          command = "git commit --fixup={{.SelectedLocalCommit.Hash}}";
          description = "Create fixup commit for selected commit";
          loadingText = "Creating fixup commit...";
        }
        {
          key = "V";
          context = "localBranches";
          command = "gh pr view --web {{.SelectedLocalBranch.Name}}";
          description = "View PR in browser";
        }
        {
          # 組み込みキー (R: reword with editor / O: PR 作成オプション / P: push) を
          # 奪わないようメニューへ退避。メニュー内は現在の context に合う項目だけ出る
          key = "<c-g>";
          description = "Extra commands";
          commandMenu = [
            {
              key = "r";
              context = "commits";
              command = "git rebase -i {{.SelectedLocalCommit.Hash}}~1";
              description = "Interactive rebase from this commit";
              output = "terminal";
            }
            {
              key = "o";
              context = "localBranches";
              command = "gh pr checkout {{.SelectedLocalBranch.Name}}";
              description = "Checkout GitHub PR";
              loadingText = "Checking out PR...";
            }
            {
              key = "p";
              context = "localBranches";
              command = "git push --force-with-lease origin {{.SelectedLocalBranch.Name}}";
              description = "Force push with lease";
              loadingText = "Force pushing...";
            }
          ];
        }
      ];
    };
  };
}
