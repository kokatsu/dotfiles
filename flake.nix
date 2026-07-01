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

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cli-tools = {
      url = "github:kokatsu/cli-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cc-statusline = {
      url = "github:kokatsu/cc-statusline";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Renovate: datasource=github-releases depName=modem-dev/hunk
    hunk = {
      url = "github:modem-dev/hunk/v0.16.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # https://github.com/NousResearch/hermes-agent
    # Renovate: datasource=github-releases depName=NousResearch/hermes-agent
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.6.19";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # UnoCSS LSP (上流が flake を提供しているため自前ビルドから移行)
    # https://github.com/xna00/unocss-language-server
    # nixpkgs.follows は付けない: package.nix が pnpm.fetchDeps の offline store を
    # 上流 pin の pnpm バージョンに密結合しており、別 nixpkgs だと
    # ERR_PNPM_NO_OFFLINE_TARBALL でビルドが壊れるため。
    # Renovate: datasource=github-releases depName=xna00/unocss-language-server
    unocss-language-server = {
      url = "github:xna00/unocss-language-server/v0.1.9";
    };

    # MoonBit ツールチェーン (公式 nixpkgs 未収録のためコミュニティ overlay を使用)
    # https://github.com/moonbit-community/moonbit-overlay
    # overlay 自体は master 追従 (パッケージング修正を取り込む) だが、
    # MoonBit のバージョンは nix/home/packages.nix の属性パスでピン留めする
    moonbit-overlay = {
      url = "github:moonbit-community/moonbit-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    # x86_64-darwin (Intel Mac) は不使用のため除外
    darwinSystems = ["aarch64-darwin"];
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
    customOverlays = import ./nix/overlays {inherit inputs;};

    # 共通オーバーレイ (全プラットフォーム)
    commonOverlays = [
      # upstream overlay (pkgs.moonbit-bin.* を生やす)
      inputs.moonbit-overlay.overlays.default
      customOverlays.biome
      customOverlays.cli-tools
      customOverlays.cc-statusline
      customOverlays.claude-code
      customOverlays.codex
      customOverlays.cssmodules-language-server
      customOverlays.dcd
      customOverlays.deck-slides
      customOverlays.difftastic
      customOverlays.direnv-no-check
      customOverlays.git-graph-fork
      customOverlays.hermes-agent
      customOverlays.kakehashi
      customOverlays.mise
      customOverlays.octorus
      customOverlays.pipx-no-check
      customOverlays.rgx-cli
      customOverlays.textlint-rule-preset-ai-writing
      customOverlays.tmux-focus-crash-fix
      customOverlays.unocss-language-server
      customOverlays.vite-plus
      customOverlays.vscode-langservers-detect-module-fix
      customOverlays.vue-language-server-pin
      customOverlays.x-api-playground
      customOverlays.yazi
    ];

    # CI用ヘルパー
    mkCIConfig = system: let
      isDarwin = builtins.elem system darwinSystems;
    in
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            # vue-language-server (3.2.x) がビルド時にのみ使う pnpm。
            # nixpkgs が patched pnpm_10 に bump したら削除する。
            permittedInsecurePackages = ["pnpm-10.34.0"];
          };
          overlays =
            commonOverlays
            ++ (
              if isDarwin
              then darwinOnlyOverlays
              else linuxOnlyOverlays
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

    # Linux専用オーバーレイ (WSL等)
    linuxOnlyOverlays = [
      customOverlays.win32yank
    ];

    # CI の hash 検証用マニフェスト。
    # binary-releases.nix の mkBinaryRelease 製パッケージを attrNames で自動収集し、
    # 各パッケージの passthru.hashTargets (全プラットフォームの url + 現在の hash) を
    # JSON で公開する。`.github/workflows/pr.yml` の verify ステップが
    # `nix eval --json .#hashUpdateManifest` で読み取り、汎用ループで照合する。
    # 新しい binary ツールを追加しても、ここと CI の編集は不要 (overlay 定義だけで完結)。
    hashUpdateManifest = let
      # binary-releases.nix の overlay 群は nixpkgs (prev) のみに依存し相互依存も
      # ないため、moonbit-overlay 等の input を巻き込まず最小構成で評価できる。
      binaryReleaseOverlays = import ./nix/overlays/binary-releases.nix;
      manifestPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = builtins.attrValues binaryReleaseOverlays;
      };
      binaryNames = builtins.attrNames binaryReleaseOverlays;
    in
      lib.filterAttrs (_: v: v != null)
      (lib.genAttrs binaryNames (n: manifestPkgs.${n}.hashTargets or null));
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
          config = {
            allowUnfree = true;
            # vue-language-server (3.2.x) がビルド時にのみ使う pnpm。
            # nixpkgs が patched pnpm_10 に bump したら削除する。
            permittedInsecurePackages = ["pnpm-10.34.0"];
          };
          overlays =
            commonOverlays
            ++ (
              if isCurrentDarwin
              then darwinOnlyOverlays
              else linuxOnlyOverlays
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

    # CI の hash 検証用マニフェスト (上の let で定義)
    inherit hashUpdateManifest;
  };
}
