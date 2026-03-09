{
  config,
  lib,
  pkgs,
  ...
}: {
  # Home ManagerのZsh管理を無効化し、既存設定を使用
  programs.zsh.enable = false;

  home = {
    activation = {
      # config.d / functions.d ディレクトリを作成（存在しない場合）
      createZshExtraDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD mkdir -p "${config.xdg.configHome}/zsh/config.d"
        $DRY_RUN_CMD mkdir -p "${config.xdg.configHome}/zsh/functions.d"
      '';

      # zimfw モジュールをインストール (.zimrc に定義された未インストールモジュールを取得)
      zimfwInstall = lib.hm.dag.entryAfter ["linkGeneration"] ''
        ZIM_HOME="${config.xdg.configHome}/zsh/.zim"
        ZIM_CONFIG_FILE="${config.xdg.configHome}/zsh/.zimrc"

        # zimfw.zsh が未ダウンロードの場合は取得
        if [ ! -e "$ZIM_HOME/zimfw.zsh" ]; then
          $DRY_RUN_CMD mkdir -p "$ZIM_HOME"
          $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fsSL -o "$ZIM_HOME/zimfw.zsh" \
            https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
        fi

        # 未インストールのモジュールをインストール
        $DRY_RUN_CMD ${pkgs.zsh}/bin/zsh -c \
          "ZIM_HOME='$ZIM_HOME' ZIM_CONFIG_FILE='$ZIM_CONFIG_FILE' source '$ZIM_HOME/zimfw.zsh' install"
      '';
    };

    # 既存のzsh設定をシンボリックリンク
    file = {
      "${config.xdg.configHome}/zsh/.zshrc".source = ../../../.config/zsh/.zshrc;
      "${config.xdg.configHome}/zsh/.zimrc".source = ../../../.config/zsh/.zimrc;
      "${config.xdg.configHome}/zsh/functions.zsh".source = ../../../.config/zsh/functions.zsh;
      "${config.xdg.configHome}/zeno/config.ts".source = ../../../.config/zeno/config.ts;
      "${config.xdg.configHome}/zsh/darwin.zsh".source = ../../../.config/zsh/darwin.zsh;
      "${config.xdg.configHome}/zsh/linux.zsh".source = ../../../.config/zsh/linux.zsh;
      "${config.xdg.configHome}/zsh/wezterm-integration.sh".source = ../../../.config/zsh/wezterm-integration.sh;

      # $ZDOTDIR/.zshenv - Nix環境とZDOTDIR設定
      # ~/.zshenv は使用せず、$ZDOTDIR/.zshenv に全ての設定を集約
      "${config.xdg.configHome}/zsh/.zshenv".text = ''
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
        # 親シェルから継承された場合にスキップされるのを防ぐため、ガード変数をリセット
        unset __HM_SESS_VARS_SOURCED
        if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
          . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
        fi

        # XDG
        export XDG_CONFIG_HOME="$HOME/.config"
        export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
      '';

      # ~/.zshenv - ZDOTDIRの設定と $ZDOTDIR/.zshenv の読み込み
      # 新しいターミナルでは ZDOTDIR が未設定のため ~/.zshenv が読み込まれる
      # zsh は zshenv を一度しか読み込まないため、ここで $ZDOTDIR/.zshenv を source する
      ".zshenv".text = ''
        export ZDOTDIR="$HOME/.config/zsh"
        [ -f "$ZDOTDIR/.zshenv" ] && . "$ZDOTDIR/.zshenv"
      '';
    };
  };
}
