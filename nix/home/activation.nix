{
  pkgs,
  lib,
  config,
  inputs,
  dotfilesDir ? "",
  isCI ? false,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.stdenv.hostPlatform) system;
  validDotfilesDir =
    if isCI
    then "/tmp/dotfiles"
    else if dotfilesDir == ""
    then throw "dotfilesDir is empty. Did you forget --impure flag?"
    else dotfilesDir;
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

    # codex: git管理の設定 (tui等) とローカルの [projects] をマージ
    mergeCodexConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      CODEX_DIR="$HOME/.config/codex"
      BASE="${validDotfilesDir}/.config/codex/config.toml"
      TARGET="$CODEX_DIR/config.toml"
      $DRY_RUN_CMD mkdir -p "$CODEX_DIR"
      if [ -f "$TARGET" ]; then
        # 既存の [projects] セクションを抽出
        # 前提: [projects.*] セクションがファイル末尾にあること (後続セクションも含まれる)
        PROJECTS=$(${pkgs.gnused}/bin/sed -n '/^\[projects[."\[]/,$ p' "$TARGET")
        $DRY_RUN_CMD cp "$BASE" "$TARGET"
        if [ -n "$PROJECTS" ]; then
          printf '\n%s\n' "$PROJECTS" >> "$TARGET"
        fi
      else
        $DRY_RUN_CMD cp "$BASE" "$TARGET"
      fi
    '';

    # WezTerm: WSL → Windows 側に設定ファイルをコピー (home-manager switch で自動反映)
    copyWezTermConfig = lib.mkIf (!isDarwin) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WINUSER=$(/mnt/c/Windows/System32/cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
      WEZTERM_DIR="/mnt/c/Users/$WINUSER/.config/wezterm"
      if [ -d "/mnt/c/Users/$WINUSER" ]; then
        $DRY_RUN_CMD mkdir -p "$WEZTERM_DIR"
        for f in "$HOME/.config/wezterm/"*.lua; do
          [ -f "$f" ] && $DRY_RUN_CMD cp -f "$f" "$WEZTERM_DIR/"
        done
      fi
    '');

    # WezTerm.app を /Applications にリンク (Dock対応)
    linkWezTermApp = lib.mkIf (isDarwin && !isCI) (lib.hm.dag.entryAfter ["linkGeneration"] ''
      WEZTERM_APP="${inputs.wezterm.packages.${system}.default}/Applications/WezTerm.app"
      if [ -d "$WEZTERM_APP" ]; then
        $DRY_RUN_CMD rm -f /Applications/WezTerm.app
        $DRY_RUN_CMD ln -sf "$WEZTERM_APP" /Applications/WezTerm.app
      fi
    '');

    # cmux: Ghostty設定の上書き (実ファイルとしてコピー)
    # cmuxのreadConfigFileはシンボリンクを拒否するためhome.fileでは不可
    # 読み込み順: ~/.config/ghostty/config → com.cmuxterm.app/config (後勝ち)
    copyCmuxGhosttyConfig = lib.mkIf isDarwin (lib.hm.dag.entryAfter ["linkGeneration"] ''
            CMUX_DIR="$HOME/Library/Application Support/com.cmuxterm.app"
            $DRY_RUN_CMD mkdir -p "$CMUX_DIR"
            $DRY_RUN_CMD cat > "$CMUX_DIR/config" << 'CMUX_EOF'
      window-padding-x = 20
      window-padding-y = 5
      window-padding-balance = true
      window-theme = ghostty
      background-opacity = 0.65
      CMUX_EOF
    '');

    # Karabiner-Elements: 設定ディレクトリを作成 (macOS only)
    # karabiner.json は karabiner.ts (TypeScript) で生成
    ensureKarabinerDir = lib.mkIf isDarwin (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/.config/karabiner"
      ''
    );
  };
}
