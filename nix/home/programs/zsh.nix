{
  config,
  lib,
  pkgs,
  validDotfilesDir,
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

      # config.d / functions.d のgit管理外ファイルを作業ツリーからコピーする。
      setupZshExtraFiles = lib.hm.dag.entryAfter ["linkGeneration"] ''
        for subdir in config.d functions.d; do
          SOURCE="${validDotfilesDir}/.config/zsh/$subdir"
          TARGET="${config.xdg.configHome}/zsh/$subdir"
          if [ -d "$SOURCE" ]; then
            $DRY_RUN_CMD mkdir -p "$TARGET"
            for f in "$SOURCE"/*.zsh; do
              [ -f "$f" ] && $DRY_RUN_CMD cp "$f" "$TARGET/" 2>/dev/null || true
            done
          fi
        done
      '';

      # zimfw モジュールをインストール (.zimrc に定義された未インストールモジュールを取得)
      zimfwInstall = lib.hm.dag.entryAfter ["linkGeneration"] ''
        ZIM_HOME="${config.xdg.configHome}/zsh/.zim"
        ZIM_CONFIG_FILE="${config.xdg.configHome}/zsh/.zimrc"

        # .zimrc の中身が前回と変わった場合のみ install を走らせる。
        # 毎回走らせると zsh 5.9 + macOS の SIGCHLD race で getoutput がハングしやすいため。
        # symlink 先 (store path) は中身が同じでも変わるので、内容で比較する。
        LAST_ZIMRC="$ZIM_HOME/.last_zimrc"
        if [ ! -e "$ZIM_HOME/init.zsh" ] || ! cmp -s "$ZIM_CONFIG_FILE" "$LAST_ZIMRC" 2>/dev/null; then
          if [ -n "$DRY_RUN_CMD" ]; then
            echo "$DRY_RUN_CMD ${pkgs.zsh}/bin/zsh -c 'source $ZIM_HOME/zimfw.zsh install'"
          else
            ${pkgs.zsh}/bin/zsh -c \
              "ZIM_HOME='$ZIM_HOME' ZIM_CONFIG_FILE='$ZIM_CONFIG_FILE' source '$ZIM_HOME/zimfw.zsh' install" &
            ZIMFW_PID=$!
            # zsh 5.9 macOS の getoutput SIGCHLD race ワークアラウンド:
            # ハングした waitforpid を SIGCHLD で起こし続ける (入れ子分早く起こすため短い間隔)
            (
              while kill -0 $ZIMFW_PID 2>/dev/null; do
                sleep 0.2
                pkill -CHLD -f "source.*zimfw\.zsh.*install" 2>/dev/null || true
              done
            ) &
            WATCHDOG_PID=$!
            wait $ZIMFW_PID || true
            kill $WATCHDOG_PID 2>/dev/null || true
            wait $WATCHDOG_PID 2>/dev/null || true
            install -m 644 "$ZIM_CONFIG_FILE" "$LAST_ZIMRC"
          fi
        fi

        # zeno の互換性パッチと Deno cache を冪等に準備する。
        # cache の取得失敗だけで Home Manager 全体を中断せず、次回に再試行する。
        if ! $DRY_RUN_CMD "${config.xdg.configHome}/zsh/scripts/prepare-zeno" "$ZIM_HOME" "${pkgs.deno}/bin/deno"; then
          echo "warning: failed to prepare zeno; retry with zimfw init" >&2
        fi
      '';
    };

    # 既存のzsh設定をシンボリックリンク
    file = {
      # zimfw本体はflake.lockで固定されたnixpkgsのパッケージを使用する。
      # .zimrcに定義した各moduleの取得はzimfw自身が管理する。
      "${config.xdg.configHome}/zsh/.zim/zimfw.zsh" = {
        source = "${pkgs.zimfw}/zimfw.zsh";
        force = true;
      };
      "${config.xdg.configHome}/zsh/.zshrc".source = ../../../.config/zsh/.zshrc;
      "${config.xdg.configHome}/zsh/.zimrc".source = ../../../.config/zsh/.zimrc;
      "${config.xdg.configHome}/zsh/scripts/prepare-zeno" = {
        source = ../../../.config/zsh/scripts/prepare-zeno;
        executable = true;
      };

      # Catppuccin palette 由来の色変数 (fzf / zoxide 等で利用)
      "${config.xdg.configHome}/zsh/catppuccin-colors.zsh".text = let
        p = config.catppuccinLib.palettes.${config.catppuccin.flavor};
      in ''
        # Generated from catppuccin.flavor = ${config.catppuccin.flavor}
        export FZF_CATPPUCCIN_COLORS="--color=bg+:${p.surface0.hex},bg:${p.base.hex},spinner:${p.rosewater.hex},hl:${p.red.hex} --color=fg:${p.text.hex},header:${p.red.hex},info:${p.mauve.hex},pointer:${p.rosewater.hex} --color=marker:${p.lavender.hex},fg+:${p.text.hex},prompt:${p.mauve.hex},hl+:${p.red.hex} --color=selected-bg:${p.surface1.hex} --color=border:${p.overlay0.hex},label:${p.text.hex}"
      '';
      "${config.xdg.configHome}/zsh/functions.zsh".source = ../../../.config/zsh/functions.zsh;
      "${config.xdg.configHome}/zeno/config.ts".source = ../../../.config/zeno/config.ts;
      "${config.xdg.configHome}/zsh/darwin.zsh".source = ../../../.config/zsh/darwin.zsh;
      "${config.xdg.configHome}/zsh/linux.zsh".source = ../../../.config/zsh/linux.zsh;
      "${config.xdg.configHome}/zsh/wezterm-integration.sh".source = ../../../.config/zsh/wezterm-integration.sh;

      # $ZDOTDIR/.zshenv - Nix環境とZDOTDIR設定
      # ~/.zshenv は使用せず、$ZDOTDIR/.zshenv に全ての設定を集約
      "${config.xdg.configHome}/zsh/.zshenv".text = ''
        # PATH/fpath の重複を排除 (先勝ち = 優先度の高い方を残す)
        # 下の hm-session-vars 再 source と nix-profile prepend、config.d/*.zsh の
        # 無条件 PATH 追加により、シェルをネストするたび PATH が 1 階層 +16 で
        # 増殖する (herdr → tmux → Claude Code → シェル で顕著)。
        # 非対話シェルでも効かせたいので .zshrc ではなく .zshenv の先頭に置く。
        typeset -gU path fpath PATH

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
        elif [ -e "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
          . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
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
