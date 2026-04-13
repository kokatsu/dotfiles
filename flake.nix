{
  description = "Nix-managed dotfiles for macOS and Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05"; # Ruby 3.2用 (nixpkgs-unstable で ruby_3_2 が削除されたため)

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Fork: unfocused split pane の opacity/fill 設定を追加
    # https://github.com/kokatsu/wezterm/tree/feat/unfocused-split-opacity
    wezterm = {
      url = "github:kokatsu/wezterm/feat/unfocused-split-opacity?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-stable,
    nix-darwin,
    home-manager,
    catppuccin,
    ...
  }: let
    # 環境変数から読み込み (--impure フラグが必要)
    # sudo実行時はSUDO_USERを優先
    sudoUser = builtins.getEnv "SUDO_USER";
    username = builtins.getEnv "USER";
    hostname = builtins.getEnv "HOSTNAME";
    dotfilesDir = builtins.getEnv "PWD"; # dotfilesディレクトリ (git管理外ファイル用)

    # サポートするシステム
    darwinSystems = ["aarch64-darwin" "x86_64-darwin"];
    linuxSystems = ["x86_64-linux" "aarch64-linux"];
    allSystems = darwinSystems ++ linuxSystems;

    # フォールバック: SUDO_USER > USER > "user"
    finalUsername =
      if sudoUser != ""
      then sudoUser
      else if username == "" || username == "root"
      then "user"
      else username;
    finalHostname =
      if hostname == ""
      then "nixos"
      else hostname;

    # 現在のシステムを検出 (--impure 必須)
    inherit (builtins) currentSystem;
    isCurrentDarwin = builtins.elem currentSystem darwinSystems;

    # システムごとにpkgsを取得するヘルパー
    inherit (nixpkgs) lib;
    forAllSystems = lib.genAttrs allSystems;
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    stablePkgsFor = system: nixpkgs-stable.legacyPackages.${system};

    # カスタムオーバーレイ
    customOverlays = import ./nix/overlays;

    # 共通オーバーレイ (全プラットフォーム)
    commonOverlays = [
      customOverlays.cc-statusline
      customOverlays.cc-filter
      customOverlays.daily
      customOverlays.claude-code
      customOverlays.cssmodules-language-server
      customOverlays.dcd
      customOverlays.deck
      customOverlays.git-graph-fork
      customOverlays.kakehashi
      customOverlays.octorus
      customOverlays.playwright-cli
      customOverlays.rgx-cli
      customOverlays.takt
      customOverlays.termframe
      customOverlays.unocss-language-server
      customOverlays.vue-language-server-pin
      customOverlays.win32yank
      customOverlays.x-api-playground
    ];

    # CI用ヘルパー
    mkCIConfig = system: let
      isDarwin = builtins.elem system darwinSystems;
    in
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays =
            commonOverlays
            ++ (
              if isDarwin
              then darwinOnlyOverlays
              else []
            );
        };
        modules = [./nix/home catppuccin.homeModules.catppuccin];
        extraSpecialArgs = {
          inherit inputs self;
          username = "ci";
          isCI = true;
          dotfilesDir = "/tmp/dotfiles";
          stablePkgs = stablePkgsFor system;
        };
      };

    # Darwin専用オーバーレイ (ビルド修正)
    darwinOnlyOverlays = [
      customOverlays.cava-darwin-fix
      customOverlays.jp2a-darwin-fix
      customOverlays.ldc-darwin-fix
    ];
  in {
    # macOS (nix-darwin + home-manager)
    darwinConfigurations.${finalHostname} = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./nix/darwin
        home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = commonOverlays ++ darwinOnlyOverlays;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            sharedModules = [catppuccin.homeModules.catppuccin];
            users.${finalUsername} = import ./nix/home;
            extraSpecialArgs = {
              inherit inputs self dotfilesDir;
              username = finalUsername;
              isCI = false;
              stablePkgs = stablePkgsFor "aarch64-darwin";
            };
          };
        }
      ];
      specialArgs = {
        inherit inputs;
        username = finalUsername;
      };
    };

    # home-manager設定
    homeConfigurations = {
      # 実際のユーザー用 (自動システム検出、--impure必須)
      ${finalUsername} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = currentSystem;
          config.allowUnfree = true;
          overlays =
            commonOverlays
            ++ (
              if isCurrentDarwin
              then darwinOnlyOverlays
              else []
            );
        };
        modules = [./nix/home catppuccin.homeModules.catppuccin];
        extraSpecialArgs = {
          inherit inputs self dotfilesDir;
          username = finalUsername;
          isCI = false;
          stablePkgs = stablePkgsFor currentSystem;
        };
      };

      # CI用 (純粋評価、ビルドテスト用)
      "ci-linux" = mkCIConfig "x86_64-linux";
      "ci-darwin" = mkCIConfig "aarch64-darwin";
    };

    # 開発シェル
    devShells = forAllSystems (system: {
      default = (pkgsFor system).mkShell {
        packages = with (pkgsFor system); [
          neovim # Plugin smoke tests
          nil # Nix LSP
          nixd # Alternative Nix LSP
          alejandra # Nix formatter
        ];
      };
    });

    # フォーマッター
    formatter = forAllSystems (system: (pkgsFor system).alejandra);
  };
}
