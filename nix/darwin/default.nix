{
  pkgs,
  username,
  ...
}: {
  # Nix設定 (Determinate Nix使用のため無効化)
  nix.enable = false;

  # nixpkgsの設定
  nixpkgs.config.allowUnfree = true;

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
    };
    taps = [];
    brews = [];
    casks = [
      "clipy"
      "docker-desktop"
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

  # フォント
  fonts.packages = with pkgs; [
    hackgen-nf-font
    nerd-fonts.fira-code
    nerd-fonts.symbols-only
  ];
}
