{
  config,
  lib,
  ...
}: {
  # Home ManagerのZsh管理を無効化し、既存設定を使用
  programs.zsh.enable = false;

  # config.d / functions.d ディレクトリを作成（存在しない場合）
  home.activation.createZshExtraDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD mkdir -p "${config.xdg.configHome}/zsh/config.d"
    $DRY_RUN_CMD mkdir -p "${config.xdg.configHome}/zsh/functions.d"
  '';

  # 既存のzsh設定をシンボリックリンク
  home.file = {
    "${config.xdg.configHome}/zsh/.zshrc".source = ../../../.config/zsh/.zshrc;
    "${config.xdg.configHome}/zsh/.zimrc".source = ../../../.config/zsh/.zimrc;
    "${config.xdg.configHome}/zsh/aliases.zsh".source = ../../../.config/zsh/aliases.zsh;
    "${config.xdg.configHome}/zsh/darwin.zsh".source = ../../../.config/zsh/darwin.zsh;
    "${config.xdg.configHome}/zsh/linux.zsh".source = ../../../.config/zsh/linux.zsh;
    "${config.xdg.configHome}/zsh/wezterm-integration.sh".source = ../../../.config/zsh/wezterm-integration.sh;

    # $ZDOTDIR/.zshenv - ZDOTDIRが既に設定されている場合に読み込まれる
    "${config.xdg.configHome}/zsh/.zshenv".text = ''
      # /etc/zsh/zshrc の compinit をスキップ
      skip_global_compinit=1
    '';

    # ~/.zshenv - Nix環境とZDOTDIR設定
    ".zshenv".text = ''
      # /etc/zshrcをスキップ (nix-darwinが生成するcompinit呼び出しを回避)
      # Zimfwのcompletionモジュールが補完を管理する
      export NOSYSZSHRC=1
      skip_global_compinit=1

      # Nix
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi

      # Nix profile PATH (シングルユーザーインストール用)
      if [ -e "$HOME/.nix-profile/bin" ]; then
        export PATH="$HOME/.nix-profile/bin:$PATH"
      fi

      # Home Manager session variables
      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi

      # XDG
      export XDG_CONFIG_HOME="$HOME/.config"
      export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
    '';
  };
}
