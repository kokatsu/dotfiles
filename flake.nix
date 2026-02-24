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

    # Fork: unfocused split pane の opacity/fill 設定を追加
    # https://github.com/kokatsu/wezterm/tree/feat/unfocused-split-opacity
    wezterm = {
      url = "github:kokatsu/wezterm/feat/unfocused-split-opacity?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-chill = {
      url = "github:davidbeesley/claude-chill";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kakehashi = {
      url = "github:atusy/kakehashi";
      # nixpkgs.followsを外してkakehashi側のnixpkgsを使用（ビルドキャッシュ効率化）
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

    # カスタムオーバーレイ
    customOverlays = import ./nix/overlays;

    # 共通オーバーレイ (全プラットフォーム)
    commonOverlays = [
      inputs.helix.overlays.default
      inputs.neovim-nightly-overlay.overlays.default
      customOverlays.agent-browser
      customOverlays.biome
      customOverlays.cc-statusline
      customOverlays.ccusage
      customOverlays.claude-code
      customOverlays.cssmodules-language-server
      customOverlays.deck
      customOverlays.deno
      customOverlays.git-graph-fork
      customOverlays.keifu
      customOverlays.marksman-binary
      customOverlays.octorus
      customOverlays.playwright-browsers-fix
      customOverlays.playwright-cli
      customOverlays.secretlint
      customOverlays.termframe
      customOverlays.textlint
      customOverlays.unocss-language-server
      customOverlays.vue-language-server-pin
      customOverlays.x-api-playground
    ];

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
        modules = [./nix/home];
        extraSpecialArgs = {
          inherit inputs self dotfilesDir;
          username = finalUsername;
          isCI = false;
          stablePkgs = stablePkgsFor currentSystem;
        };
      };

      # CI用 (純粋評価、ビルドテスト用)
      "ci-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
          overlays = commonOverlays;
        };
        modules = [./nix/home];
        extraSpecialArgs = {
          inherit inputs self;
          username = "ci";
          isCI = true;
          dotfilesDir = "/tmp/dotfiles";
          stablePkgs = stablePkgsFor "x86_64-linux";
        };
      };

      "ci-darwin" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
          overlays = commonOverlays ++ darwinOnlyOverlays;
        };
        modules = [./nix/home];
        extraSpecialArgs = {
          inherit inputs self;
          username = "ci";
          isCI = true;
          dotfilesDir = "/tmp/dotfiles";
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
  };
}
