{
  pkgs,
  lib,
  config,
  validDotfilesDir,
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  home.activation = {
    # win32yank.exe を ~/bin/ にコピー (WSL クリップボード連携)
    copyWin32yank = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p "$HOME/bin"
      $DRY_RUN_CMD cp -f "${pkgs.win32yank}/bin/win32yank.exe" "$HOME/bin/win32yank.exe"
      $DRY_RUN_CMD chmod +x "$HOME/bin/win32yank.exe"
    '');
    # WSL2 で不要な PulseAudio サービスをマスク
    maskPulseAudio = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user mask --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
    '');

    # メディアファイル (背景画像、ロゴ) をコピー (git管理外)
    setupAssets = lib.hm.dag.entryAfter ["linkGeneration"] ''
      SOURCE="${validDotfilesDir}/.config/assets"
      TARGET="$HOME/.config/assets"
      if [ -d "$SOURCE" ]; then
        $DRY_RUN_CMD mkdir -p "$TARGET/backgrounds" "$TARGET/logos"
        for subdir in backgrounds logos; do
          if [ -d "$SOURCE/$subdir" ]; then
            $DRY_RUN_CMD cp -r "$SOURCE/$subdir/"* "$TARGET/$subdir/" 2>/dev/null || true
          fi
        done
      fi
    '';

    # zsh config.d / functions.d をコピー (git管理外ファイル用)
    setupZshExtraFiles = lib.hm.dag.entryAfter ["linkGeneration"] ''
      for subdir in config.d functions.d; do
        SOURCE="${validDotfilesDir}/.config/zsh/$subdir"
        TARGET="$HOME/.config/zsh/$subdir"
        if [ -d "$SOURCE" ]; then
          $DRY_RUN_CMD mkdir -p "$TARGET"
          for f in "$SOURCE"/*.zsh; do
            [ -f "$f" ] && $DRY_RUN_CMD cp "$f" "$TARGET/" 2>/dev/null || true
          done
        fi
      done
    '';

    # Playwright ブラウザを Nix store からシンボリックリンク (agent-browser 用)
    # agent-browser は PLAYWRIGHT_BROWSERS_PATH を無視するため、デフォルトパスにリンクを作成
    setupPlaywrightBrowsers = lib.hm.dag.entryAfter ["linkGeneration"] ''
      PLAYWRIGHT_CACHE="${
        if isDarwin
        then "$HOME/Library/Caches/ms-playwright"
        else "$HOME/.cache/ms-playwright"
      }"
      PLAYWRIGHT_BROWSERS="${pkgs.playwright-driver.browsers}"
      $DRY_RUN_CMD mkdir -p "$PLAYWRIGHT_CACHE"
      for browser in "$PLAYWRIGHT_BROWSERS"/*; do
        name=$(basename "$browser")
        target="$PLAYWRIGHT_CACHE/$name"
        if [ -L "$target" ]; then
          $DRY_RUN_CMD rm "$target"
        fi
        $DRY_RUN_CMD ln -sf "$browser" "$target"
      done
    '';

    # hermes-agent: catppuccin.flavor に追従して display.skin を書き戻す
    # 現在値と差分があるときだけ呼ぶ (process spawn と config.yaml の mtime churn を回避)
    applyHermesSkin = lib.hm.dag.entryAfter ["linkGeneration"] ''
      DESIRED="catppuccin-${config.catppuccin.flavor}"
      CONFIG="${config.xdg.configHome}/hermes/config.yaml"
      CURRENT=""
      if [ -f "$CONFIG" ]; then
        CURRENT=$(${pkgs.gnugrep}/bin/grep -E '^[[:space:]]*skin:[[:space:]]*' "$CONFIG" \
          | ${pkgs.gnused}/bin/sed -E 's/^[[:space:]]*skin:[[:space:]]*"?([^"#]+)"?.*/\1/' \
          | tr -d '[:space:]' || true)
      fi
      if [ "$CURRENT" != "$DESIRED" ]; then
        $DRY_RUN_CMD env HERMES_HOME="${config.xdg.configHome}/hermes" \
          "${pkgs.hermes-agent}/bin/hermes" config set display.skin "$DESIRED" > /dev/null
      fi
    '';

    # codex: git管理の設定 (tui等) と Codex が書き戻すローカル状態をマージ
    mergeCodexConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      CODEX_DIR="$HOME/.config/codex"
      BASE="${validDotfilesDir}/.config/codex/config.toml"
      TARGET="$CODEX_DIR/config.toml"
      $DRY_RUN_CMD mkdir -p "$CODEX_DIR"
      if [ -f "$TARGET" ]; then
        # セクション順に依存せず、Codex が管理するローカル状態だけを抽出する。
        LOCAL_STATE=$(${pkgs.gawk}/bin/awk '
          /^\[\[?/ {
            keep = 0
            if ($0 ~ /^\[\[?projects(\.|\])/) keep = 1
            if ($0 ~ /^\[\[?tui\.model_availability_nux\]\]?$/) keep = 1
            if ($0 ~ /^\[\[?notice(\.|\])/) keep = 1
            if ($0 ~ /^\[\[?hooks\.state(\.|\])/) keep = 1
          }
          keep { print }
        ' "$TARGET")
        $DRY_RUN_CMD cp "$BASE" "$TARGET"
        if [ -n "$LOCAL_STATE" ]; then
          if [ -n "$DRY_RUN_CMD" ]; then
            echo "Preserving Codex local state in $TARGET"
          else
            printf '\n%s\n' "$LOCAL_STATE" >> "$TARGET"
          fi
        fi
      else
        $DRY_RUN_CMD cp "$BASE" "$TARGET"
      fi

      RULES_DIR="$CODEX_DIR/rules"
      RULES_BASE="${validDotfilesDir}/.config/codex/rules/managed.rules"
      RULES_TARGET="$RULES_DIR/managed.rules"
      LOCAL_RULES_TARGET="$RULES_DIR/default.rules"
      $DRY_RUN_CMD mkdir -p "$RULES_DIR"

      # 旧構成の管理ルールを default.rules から取り除き、Codex が追記した
      # 1 行形式のローカル許可だけを初回移行時に残す。
      if [ -f "$LOCAL_RULES_TARGET" ] && \
        [ "$(${pkgs.coreutils}/bin/head -n 1 "$LOCAL_RULES_TARGET")" = "# Read-only git inspection commands." ]; then
        LOCAL_RULES=$(${pkgs.gnugrep}/bin/grep '^prefix_rule(pattern=' "$LOCAL_RULES_TARGET" || true)
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "Migrating Codex-local rules in $LOCAL_RULES_TARGET"
        elif [ -n "$LOCAL_RULES" ]; then
          printf '%s\n' "$LOCAL_RULES" > "$LOCAL_RULES_TARGET"
        else
          ${pkgs.coreutils}/bin/rm -f "$LOCAL_RULES_TARGET"
        fi
      fi

      $DRY_RUN_CMD cp "$RULES_BASE" "$RULES_TARGET"
    '';

    # WezTerm: WSL → Windows 側に設定ファイル (.lua) を再帰コピー
    copyWezTermConfig = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WINUSER=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
      WEZTERM_DIR="/mnt/c/Users/$WINUSER/.config/wezterm"
      SRC_DIR="$HOME/.config/wezterm"
      if [ -n "$WINUSER" ] && [ -d "/mnt/c/Users/$WINUSER" ]; then
        $DRY_RUN_CMD mkdir -p "$WEZTERM_DIR"
        # -L: home-manager の symlink を辿って実体をコピー
        find -L "$SRC_DIR" -type f -name '*.lua' | while IFS= read -r f; do
          rel="''${f#$SRC_DIR/}"
          dst="$WEZTERM_DIR/$rel"
          $DRY_RUN_CMD mkdir -p "$(dirname "$dst")"
          $DRY_RUN_CMD cp -fL "$f" "$dst"
        done
      fi
    '');

    # WezTerm.app を /Applications にリンク (Dock対応)
    linkWezTermApp = lib.mkIf (isDarwin && !isCI) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WEZTERM_APP="${pkgs.wezterm}/Applications/WezTerm.app"
      if [ -d "$WEZTERM_APP" ]; then
        $DRY_RUN_CMD rm -f /Applications/WezTerm.app
        $DRY_RUN_CMD ln -sf "$WEZTERM_APP" /Applications/WezTerm.app
      fi
    '');

    # Karabiner-Elements: karabiner.ts から karabiner.json を生成 (macOS only)
    # writeToProfile() は ~/.config/karabiner/karabiner.json の既存プロファイルを上書きするため、
    # 未作成ならスタブを配置してから deno を実行する
    # CI では除外: ${pkgs.deno} が closure に入ると deno のローカルビルド (trybuild fail) を誘発する
    buildKarabinerConfig = lib.mkIf (isDarwin && !isCI) (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        KARABINER_DIR="${config.home.homeDirectory}/.config/karabiner"
        $DRY_RUN_CMD mkdir -p "$KARABINER_DIR"
        if [ ! -f "$KARABINER_DIR/karabiner.json" ]; then
          $DRY_RUN_CMD tee "$KARABINER_DIR/karabiner.json" > /dev/null <<< '{"global":{},"profiles":[{"name":"Default","selected":true}]}'
        fi
        $DRY_RUN_CMD ${pkgs.deno}/bin/deno run \
          --config "${validDotfilesDir}/karabiner-config/deno.json" \
          --allow-env --allow-read --allow-write \
          "${validDotfilesDir}/karabiner-config/karabiner.ts"
      ''
    );
  };
}
