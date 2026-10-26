{
  lib,
  username,
  ...
}: {
  # Nix設定 (Determinate Nix使用のため無効化)
  nix.enable = false;

  # Determinate Nix は追加設定を nix.custom.conf から読む。daemon は trusted-users
  # 以外がユーザー設定で足した substituter を無視するため、システム側で宣言する
  # (nix/home/nix.nix の Linux 向け設定と同じキャッシュ)。
  environment.etc."nix/nix.custom.conf".text = ''
    extra-substituters = https://kokatsu.cachix.org https://helix.cachix.org
    extra-trusted-public-keys = kokatsu.cachix.org-1:womBGQiv46ieMIq9Lll7fa06bN0CMKMjIEDIjvp8+rI= helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs=
  '';

  # nixpkgsの設定
  nixpkgs.config = {
    allowUnfree = true;
  };

  # プライマリユーザー設定 (nix-darwin 最新版で必要)
  system.primaryUser = username;

  # Homebrew (Nixで管理できないGUIアプリ用)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      # Homebrew 6.0 以降、auto_updates な cask (Chrome 等) も通常の upgrade で
      # .app ごと差し替えられる。起動中の Chrome があると新規タブが真っ白に
      # なるため、darwin-rebuild は Chrome を閉じてから実行すること。
      upgrade = true;
      # activation は sudo 経由で走るため、シェルの HOMEBREW_* は引き継がれない
      extraEnv = {
        HOMEBREW_NO_ENV_HINTS = "1";
        HOMEBREW_NO_UPDATE_REPORT_NEW = "1";
        # XDG_CONFIG_HOME も届かないので、brew がシェルと同じ trust.json を使うよう
        # 代わりに読む HOMEBREW_XDG_CONFIG_HOME を渡す (無いと ~/.homebrew に書く)
        HOMEBREW_XDG_CONFIG_HOME = "/Users/${username}/.config";
      };
    };
    # Homebrew 6.0 以降、非公式 tap は信頼が必須 (HOMEBREW_REQUIRE_TAP_TRUST が
    # デフォルト true)。`trusted = true` で Brewfile に `trusted: true` が出力され、
    # bundle がインラインで信頼を受け取る。これにより外部状態 (~/.config の
    # trust.json) に依存せず、ファイル消失による activation 失敗が起きない。
    taps = [
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
      "orbstack"
      "ghostty"
      "google-chrome"
      "google-japanese-ime"
      "karabiner-elements"
      "raycast"
      "wezterm@nightly"
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

  security = {
    # CVE-2026-111943 (eMudhra intermediate CA compromise) の対象ルートを
    # /etc/ssl/certs/ca-certificates.crt から除外する (NixOS/nixpkgs issue 576485)。
    # emSign の各ルートは NSS 側で削除済みで、ストアにない名前を並べると cacert のビルドが失敗する。
    # nix-darwin 側で同じ除外が既定になれば (nix-darwin PR 1876) 不要。
    # Determinate Nix の daemon は macos-keychain.crt を使うので、これでは守られない。
    pki.caCertificateBlacklist = [
      "Comodo AAA Services root"
    ];

    # Touch ID for sudo
    # reattach は herdr / tmux などの端末マルチプレクサ内でも Touch ID を使うため
    pam.services.sudo_local = {
      touchIdAuth = true;
      reattach = true;
    };

    # sudo が NIX_SSL_CERT_FILE を消すと、root で動く git などの OpenSSL は
    # デフォルトプロファイルの古い CA バンドルに戻り、pki.caCertificateBlacklist が効かない
    sudo.extraConfig = ''
      Defaults:root,%admin env_keep+=NIX_SSL_CERT_FILE
    '';
  };

  # ユーザー設定
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # root ユーザーの home を明示的に設定 (nix-darwin の assertion を満たすため)
  users.users.root.home = "/var/root";

  # nix-darwin の既定は $HOME/.nix-profile を固定で含むが、Home Manager 側で
  # use-xdg-base-directories を有効にしているためユーザープロファイルはこちらにある。
  # PATH・TERMINFO_DIRS・XDG_*_DIRS・NIX_PROFILES はこの一覧から生成される。
  environment.profiles = lib.mkForce [
    "$HOME/.local/state/nix/profile"
    "/run/current-system/sw"
    "/nix/var/nix/profiles/default"
  ];
}
