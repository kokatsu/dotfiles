_: {
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        showRandomTip = false;
        showBottomLine = false;
        showCommandLog = false;
        scrollHeight = 10;
        scrollPastBottom = true;
        sidePanelWidth = 0.3333;
        expandFocusedSidePanel = true;
        mainPanelSplitMode = "flexible";
        showIcons = true;
        nerdFontsVersion = "3";
        # theme は catppuccin/nix で管理
      };
      git = {
        autoFetch = true;
        autoRefresh = true;
        branchLogCmd = "git log --graph --color=always --abbrev-commit --decorate --date=relative --pretty=medium {{branchName}} --";
        pagers = [
          # difftastic 移行のため delta 連携を無効化 (戻す場合はコメント解除)
          # {pager = "delta --dark --paging=never";}
          # git config の diff.external = difft を流用 (.gitattributes でファイル型別設定も可)
          {useExternalDiffGitConfig = true;}
        ];
      };
      os = {
        editPreset = "nvim-remote";
      };
      notARepository = "skip";
      promptToReturnFromSubprocess = false;
      customCommands = [
        {
          key = "R";
          context = "commits";
          command = "git rebase -i {{.SelectedLocalCommit.Hash}}~1";
          description = "Interactive rebase from this commit";
          output = "terminal";
        }
        {
          key = "F";
          context = "files";
          command = "git commit --fixup={{.SelectedLocalCommit.Hash}}";
          description = "Create fixup commit for selected commit";
          loadingText = "Creating fixup commit...";
        }
        {
          key = "S";
          context = "commits";
          command = "git rebase -i --autosquash {{.SelectedLocalCommit.Hash}}~1";
          description = "Autosquash fixup commits";
          output = "terminal";
        }
        {
          key = "O";
          context = "localBranches";
          command = "gh pr checkout {{.SelectedLocalBranch.Name}}";
          description = "Checkout GitHub PR";
          loadingText = "Checking out PR...";
        }
        {
          key = "V";
          context = "localBranches";
          command = "gh pr view --web {{.SelectedLocalBranch.Name}}";
          description = "View PR in browser";
        }
        {
          key = "Y";
          context = "localBranches";
          command = "echo -n {{.SelectedLocalBranch.Name}} | clip.exe";
          description = "Copy branch name to clipboard";
        }
        {
          key = "Y";
          context = "commits";
          command = "echo -n {{.SelectedLocalCommit.Hash}} | clip.exe";
          description = "Copy commit hash to clipboard";
        }
        {
          key = "P";
          context = "localBranches";
          command = "git push --force-with-lease origin {{.SelectedLocalBranch.Name}}";
          description = "Force push with lease";
          loadingText = "Force pushing...";
        }
        {
          key = "f";
          context = "remotes";
          command = "git fetch --prune {{.SelectedRemote.Name}}";
          description = "Fetch and prune remote";
          loadingText = "Fetching...";
        }
      ];
      keybinding = {
        universal = {
          "scrollUpMain-alt1" = "K";
          "scrollDownMain-alt1" = "J";
        };
        commits = {
          moveDownCommit = "<c-j>";
          moveUpCommit = "<c-k>";
        };
      };
    };
  };
}
