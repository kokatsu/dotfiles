{
  config,
  lib,
  pkgs,
  inputs,
  validDotfilesDir,
  ...
}: let
  pluginDir = "${config.xdg.configHome}/zsh/plugins";
  # zeno.zsh は prepare-zeno のパッチと Deno の node_modules を自身のディレクトリへ
  # 書き込むため、ここには含めず activation で書き込み可能なコピーを置く。
  plugins = {
    completion = inputs.zim-completion;
    environment = inputs.zim-environment;
    evalcache = inputs.zsh-evalcache;
    git = inputs.zim-git;
    input = inputs.zim-input;
    termtitle = inputs.zim-termtitle;
    utility = inputs.zim-utility;
    zsh-autosuggestions = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
    zsh-completions = "${pkgs.zsh-completions}/share/zsh/site-functions";
    zsh-defer = "${pkgs.zsh-defer}/share/zsh-defer";
    zsh-history-substring-search = "${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search";
    zsh-syntax-highlighting = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
  };
in {
  # Home ManagerのZsh管理を無効化し、既存設定を使用
  programs.zsh.enable = false;

  home = {
    activation = {
      # config.d / functions.d のgit管理外ファイルを作業ツリーからコピーする。
      setupZshExtraFiles =
        lib.hm.dag.entryAfter ["linkGeneration"]
        # bash
        ''
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

      # evalcache は初期化コマンドの文字列だけをキーにするため、mise activate 等が
      # 出力に焼き込む store パス入りの PATH は世代が変わっても更新されない。
      # 世代切り替え時に消して次のシェルで再生成させる。
      # brew shellenv は store パスを含まず、同期実行のため再生成メッセージが
      # 毎回見えるので対象から外す。
      # .zshrc の ls_colors_cache も空でない限り再生成されず、catppuccin.flavor を
      # 変えても古い配色が残るため一緒に消す。
      clearZshEvalcache =
        lib.hm.dag.entryAfter ["linkGeneration"]
        # bash
        ''
          if [ -d "${config.xdg.cacheHome}/zsh-evalcache" ]; then
            $DRY_RUN_CMD find "${config.xdg.cacheHome}/zsh-evalcache" -maxdepth 1 \
              \( -name 'init-*.sh' -o -name 'init-*.sh.zwc' -o -name ls_colors_cache \) \
              ! -name 'init-brew-*' -delete
          fi
        '';

      installZeno =
        lib.hm.dag.entryAfter ["linkGeneration"]
        # bash
        ''
          ZENO_SRC="${inputs.zeno-zsh}"
          ZENO_DIR="${pluginDir}/zeno.zsh"

          # コピー元の store path を symlink で記録し、変わったときだけ入れ替える。
          if [ "$(readlink "$ZENO_DIR/.nix-source" 2>/dev/null)" != "$ZENO_SRC" ]; then
            # store からのコピーは読み取り専用で、そのままだと rm -rf できない
            [ -d "$ZENO_DIR" ] && $DRY_RUN_CMD chmod -R u+w "$ZENO_DIR"
            $DRY_RUN_CMD rm -rf "$ZENO_DIR"
            $DRY_RUN_CMD mkdir -p "${pluginDir}"
            $DRY_RUN_CMD cp -R "$ZENO_SRC" "$ZENO_DIR"
            $DRY_RUN_CMD chmod -R u+w "$ZENO_DIR"
            $DRY_RUN_CMD ln -s "$ZENO_SRC" "$ZENO_DIR/.nix-source"
          fi

          # zeno の互換性パッチと Deno cache を冪等に準備する。
          # cache の取得失敗だけで Home Manager 全体を中断せず、次回に再試行する。
          if ! $DRY_RUN_CMD "${config.xdg.configHome}/zsh/scripts/prepare-zeno" "$ZENO_DIR" "${pkgs.deno}/bin/deno"; then
            echo "warning: failed to prepare zeno; retry on next activation" >&2
          fi
        '';
    };

    # 既存のzsh設定をシンボリックリンク
    file =
      lib.mapAttrs' (name: source: lib.nameValuePair "${pluginDir}/${name}" {inherit source;}) plugins
      // {
        "${config.xdg.configHome}/zsh/.zshrc".source = ../../../.config/zsh/.zshrc;
        "${config.xdg.configHome}/zsh/scripts/prepare-zeno" = {
          source = ../../../.config/zsh/scripts/prepare-zeno;
          executable = true;
        };

        "${config.xdg.configHome}/zsh/functions.zsh".source = ../../../.config/zsh/functions.zsh;
        "${config.xdg.configHome}/zeno/config.ts".source = ../../../.config/zeno/config.ts;
        "${config.xdg.configHome}/zsh/darwin.zsh".source = ../../../.config/zsh/darwin.zsh;
        "${config.xdg.configHome}/zsh/linux.zsh".source = ../../../.config/zsh/linux.zsh;
        "${config.xdg.configHome}/zsh/wezterm-integration.sh".source = ../../../.config/zsh/wezterm-integration.sh;

        # $ZDOTDIR/.zshenv - Nix環境とZDOTDIR設定
        # ~/.zshenv は使用せず、$ZDOTDIR/.zshenv に全ての設定を集約
        "${config.xdg.configHome}/zsh/.zshenv".text =
          # bash
          ''
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
            if [ -e "${config.home.profileDirectory}/bin" ]; then
              export PATH="${config.home.profileDirectory}/bin:$PATH"
            fi

            # Home Manager session variables
            # 親シェルから継承された場合にスキップされるのを防ぐため、ガード変数をリセット
            # (standalone Home Manager のみ使うため /etc/profiles/per-user は見ない)
            unset __HM_SESS_VARS_SOURCED
            if [ -e "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
              . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
            fi
            # XDG_CONFIG_HOME / ZDOTDIR は hm-session-vars.sh と ~/.zshenv が設定する
          '';

        # ~/.zshenv - ZDOTDIRの設定と $ZDOTDIR/.zshenv の読み込み
        # 新しいターミナルでは ZDOTDIR が未設定のため ~/.zshenv が読み込まれる
        # zsh は zshenv を一度しか読み込まないため、ここで $ZDOTDIR/.zshenv を source する
        ".zshenv".text =
          # bash
          ''
            export ZDOTDIR="$HOME/.config/zsh"
            [ -f "$ZDOTDIR/.zshenv" ] && . "$ZDOTDIR/.zshenv"
          '';
      };
  };
}
