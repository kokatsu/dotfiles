{
  pkgs,
  username,
  ...
}: {
  # Nix設定 (Determinate Nix使用のため無効化)
  nix.enable = false;

  # nixpkgsの設定
  nixpkgs.config = {
    allowUnfree = true;
    # vue-language-server (3.2.x) がビルド時にのみ使う pnpm。
    # nixpkgs が patched pnpm_10 に bump したら削除する。
    permittedInsecurePackages = ["pnpm-10.34.0"];
  };

  # プライマリユーザー設定 (nix-darwin 最新版で必要)
  system.primaryUser = username;

  # システム全体のパッケージ
  environment.systemPackages = with pkgs; [
    # 基本ツール
    git
    curl
    wget
  ];

  # Homebrew (Nixで管理できないGUIアプリ用)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
      # Homebrew 5.x は `brew bundle --cleanup` に force 系フラグ必須 (非対話で
      # 未掲載パッケージを zap するため)。これがないと activation が失敗する。
      extraFlags = ["--force-cleanup"];
    };
    # Homebrew 6.0 以降、非公式 tap は信頼が必須 (HOMEBREW_REQUIRE_TAP_TRUST が
    # デフォルト true)。`trusted = true` で Brewfile に `trusted: true` が出力され、
    # bundle がインラインで信頼を受け取る。これにより外部状態 (~/.config の
    # trust.json) に依存せず、ファイル消失による activation 失敗が起きない。
    taps = [
      {
        name = "manaflow-ai/cmux";
        trusted = true;
      }
      {
        name = "vjeantet/tap";
        trusted = true;
      }
    ];
    brews = [
      # https://github.com/vjeantet/alerter
      "vjeantet/tap/alerter" # macOS通知 (Apple Silicon対応、terminal-notifierの後継)
    ];
    casks = [
      "clipy"
      "cmux"
      "orbstack"
      "ghostty"
      "google-chrome"
      "google-japanese-ime"
      "karabiner-elements"
      "raycast"
    ];
  };

  # macOS設定
  system = {
    # defaults writeの代わり
    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
      };

      dock = {
        autohide = true;
        show-recents = false;
        tilesize = 48;
      };

      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        FXPreferredViewStyle = "Nlsv"; # リスト表示
      };

      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
      };

      # App Switcher (Command+Tab) を無効化
      # Raycast Switch Windows を代わりに使用
      CustomUserPreferences = {
        "com.apple.symbolichotkeys" = {
          AppleSymbolicHotKeys = {
            # 60 = Ctrl+Space (前の入力ソースを選択)
            # herdr の prefix (ctrl+space) を OS が横取りするため無効化。
            # IME 切替には未使用 (61 = Ctrl+Opt+Space の入力メニューは残す)
            "60" = {
              enabled = false;
            };
            # 71 = Command+Tab (Move focus to active or next window)
            "71" = {
              enabled = false;
            };
          };
        };
      };
    };

    # システムバージョン (変更時にnix-darwinを再適用)
    stateVersion = 5;
  };

  # セキュリティ設定 (Touch ID for sudo)
  security.pam.services.sudo_local.touchIdAuth = true;

  # ユーザー設定
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # root ユーザーの home を明示的に設定 (nix-darwin の assertion を満たすため)
  users.users.root.home = "/var/root";
}
