{
  description = "Nix-managed dotfiles for macOS and Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05"; # Ruby 3.1用

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kakehashi = {
      url = "github:atusy/kakehashi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-stable,
    nix-darwin,
    home-manager,
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

    # node2nixで管理されるnpmパッケージ
    nodePackagesFor = system:
      import ./nix/node2nix {
        pkgs = pkgsFor system;
        inherit system;
        nodejs = (pkgsFor system).nodejs_22;
      };

    # カスタムオーバーレイ
    customOverlays = import ./nix/overlays;
  in {
    # macOS (nix-darwin + home-manager)
    darwinConfigurations.${finalHostname} = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./nix/darwin
        home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [
            inputs.neovim-nightly-overlay.overlays.default
            customOverlays.cava-darwin-fix
            customOverlays.deck
            customOverlays.git-graph-fork
            customOverlays.jp2a-darwin-fix
            customOverlays.ldc-darwin-fix
            customOverlays.termframe
          ];
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            users.${finalUsername} = import ./nix/home;
            extraSpecialArgs = {
              inherit inputs self dotfilesDir;
              username = finalUsername;
              isCI = false;
              nodePackages = nodePackagesFor "aarch64-darwin";
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
            [
              inputs.neovim-nightly-overlay.overlays.default
              customOverlays.deck
              customOverlays.git-graph-fork
              customOverlays.termframe
              customOverlays.vue-language-server-pin
            ]
            ++ (
              if isCurrentDarwin
              then [
                customOverlays.cava-darwin-fix
                customOverlays.jp2a-darwin-fix
                customOverlays.ldc-darwin-fix
              ]
              else []
            );
        };
        modules = [./nix/home];
        extraSpecialArgs = {
          inherit inputs self dotfilesDir;
          username = finalUsername;
          isCI = false;
          nodePackages = nodePackagesFor currentSystem;
          stablePkgs = stablePkgsFor currentSystem;
        };
      };

      # CI用 (純粋評価、ビルドテスト用)
      "ci-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [
            inputs.neovim-nightly-overlay.overlays.default
            customOverlays.deck
            customOverlays.git-graph-fork
            customOverlays.termframe
            customOverlays.vue-language-server-pin
          ];
        };
        modules = [./nix/home];
        extraSpecialArgs = {
          inherit inputs self;
          username = "ci";
          isCI = true;
          dotfilesDir = "/tmp/dotfiles";
          nodePackages = nodePackagesFor "x86_64-linux";
          stablePkgs = stablePkgsFor "x86_64-linux";
        };
      };

      "ci-darwin" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
          overlays = [
            inputs.neovim-nightly-overlay.overlays.default
            customOverlays.cava-darwin-fix
            customOverlays.deck
            customOverlays.git-graph-fork
            customOverlays.jp2a-darwin-fix
            customOverlays.ldc-darwin-fix
            customOverlays.termframe
            customOverlays.vue-language-server-pin
          ];
        };
        modules = [./nix/home];
        extraSpecialArgs = {
          inherit inputs self;
          username = "ci";
          isCI = true;
          dotfilesDir = "/tmp/dotfiles";
          nodePackages = nodePackagesFor "aarch64-darwin";
          stablePkgs = stablePkgsFor "aarch64-darwin";
        };
      };
    };

    # 開発シェル
    devShells = forAllSystems (system: {
      default = (pkgsFor system).mkShell {
        packages = with (pkgsFor system); [
          nil # Nix LSP
          nixd # Alternative Nix LSP
          alejandra # Nix formatter
        ];
      };
    });

    # フォーマッター
    formatter = forAllSystems (system: (pkgsFor system).alejandra);

    # node2nix更新用アプリ
    apps = forAllSystems (system: {
      update-node2nix = {
        type = "app";
        program = toString ((pkgsFor system).writeShellScript "update-node2nix" ''
          cd nix/node2nix
          exec ${(pkgsFor system).node2nix}/bin/node2nix -l package-lock.json
        '');
      };
    });
  };
}
