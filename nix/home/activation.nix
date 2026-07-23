{
  pkgs,
  lib,
  validDotfilesDir,
  isWSL,
  ...
}: {
  home.activation = {
    # win32yank.exe を ~/bin/ にコピー (WSL クリップボード連携)
    copyWin32yank = lib.mkIf isWSL (lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p "$HOME/bin"
      $DRY_RUN_CMD cp -f "${pkgs.win32yank}/bin/win32yank.exe" "$HOME/bin/win32yank.exe"
      $DRY_RUN_CMD chmod +x "$HOME/bin/win32yank.exe"
    '');
    # WSL2 で不要な PulseAudio サービスをマスク
    maskPulseAudio = lib.mkIf isWSL (lib.hm.dag.entryAfter ["writeBoundary"] ''
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
  };
}
