{
  description = "Nix-managed dotfiles for macOS and Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nix-darwin,
    home-manager,
    ...
  }: let
    # 環境変数から読み込み (--impure フラグが必要)
    username = builtins.getEnv "USER";
    hostname = builtins.getEnv "HOSTNAME";

    # フォールバック: 環境変数が空の場合
    finalUsername =
      if username == ""
      then "user"
      else username;
    finalHostname =
      if hostname == ""
      then "nixos"
      else hostname;

    # サポートするシステム
    darwinSystems = ["aarch64-darwin" "x86_64-darwin"];
    linuxSystems = ["x86_64-linux" "aarch64-linux"];
    allSystems = darwinSystems ++ linuxSystems;

    # システムごとにpkgsを取得するヘルパー
    forAllSystems = nixpkgs.lib.genAttrs allSystems;
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    # macOS (nix-darwin + home-manager)
    darwinConfigurations.${finalHostname} = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./darwin
        home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [
            inputs.neovim-nightly-overlay.overlays.default
          ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.${finalUsername} = import ./home;
          home-manager.extraSpecialArgs = {inherit inputs;};
        }
      ];
      specialArgs = {
        inherit inputs;
        username = finalUsername;
      };
    };

    # Linux/WSL (home-manager standalone)
    homeConfigurations.${finalUsername} = home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor "x86_64-linux";
      modules = [./home];
      extraSpecialArgs = {
        inherit inputs;
        username = finalUsername;
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
