{
  pkgs,
  config,
  lib,
  ...
}: {
  # Home ManagerのZsh管理を無効化し、既存設定を使用
  programs.zsh.enable = false;

  # 既存のzsh設定をシンボリックリンク
  home.file = {
    "${config.xdg.configHome}/zsh/.zshrc".source = ../../.config/zsh/.zshrc;
    "${config.xdg.configHome}/zsh/.zimrc".source = ../../.config/zsh/.zimrc;
    "${config.xdg.configHome}/zsh/aliases.zsh".source = ../../.config/zsh/aliases.zsh;
    "${config.xdg.configHome}/zsh/darwin.zsh".source = ../../.config/zsh/darwin.zsh;
    "${config.xdg.configHome}/zsh/linux.zsh".source = ../../.config/zsh/linux.zsh;
    "${config.xdg.configHome}/zsh/wezterm-integration.sh".source = ../../.config/zsh/wezterm-integration.sh;

    # .zshenv - Nix環境とZDOTDIR設定
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
