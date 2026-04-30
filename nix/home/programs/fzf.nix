_: {
  programs.fzf = {
    enable = true;
    enableZshIntegration = false; # 既存の.zshrcで管理

    # 素の fzf 起動時のファイル列挙 (FZF_DEFAULT_COMMAND)
    defaultCommand = "fd --type f --hidden --strip-cwd-prefix --exclude .git";

    # 全 fzf 起動の共通オプション (FZF_DEFAULT_OPTS)
    # 色は catppuccin/nix の programs.fzf.colors が連結するため指定しない
    defaultOptions = [
      "--height=60%"
      "--layout=reverse"
      "--border=rounded"
      "--info=inline-right"
      "--cycle"
      "--bind=ctrl-/:toggle-preview"
    ];

    # Alt+T: ファイル選択 (FZF_CTRL_T_COMMAND / FZF_CTRL_T_OPTS)
    # ※ env var 名は CTRL_T のまま (fzf 仕様)。bindkey は .zshrc で Alt+T にリマップ
    fileWidgetCommand = "fd --type f --hidden --strip-cwd-prefix --exclude .git";
    fileWidgetOptions = [
      "--scheme=path"
      "--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
      "--preview-window=right:60%:wrap"
    ];

    # Alt+C: cd 先選択 (FZF_ALT_C_COMMAND / FZF_ALT_C_OPTS)
    changeDirWidgetCommand = "fd --type d --hidden --strip-cwd-prefix --exclude .git";
    changeDirWidgetOptions = [
      "--scheme=path"
      "--preview 'eza --tree --color=always --level=2 {} | head -200'"
    ];
  };
}
