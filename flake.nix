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
      url = "github:modem-dev/hunk/v0.17.0";
      inputs.nixpkgs.follows = "nixpkgs";
      # bun2nix の既定 systems には、Nixpkgs 26.11 で削除された
      # x86_64-darwin が含まれる。実際に使用する3環境だけに限定する。
      inputs.bun2nix.inputs.systems.url = "github:nix-systems/triplet";
    };

    # https://github.com/NousResearch/hermes-agent
    # Renovate: datasource=github-releases depName=NousResearch/hermes-agent
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.7.7.2";
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
    # out-of-store symlink 用の実パス。PCごとに配置場所が異なるため
    # DOTFILES_DIR で明示できるようにし、未指定時だけカレントディレクトリを使う。
    # 後者は nix/home/default.nix で flake.nix の存在を検証するため、別ディレクトリを
    # 誤ってリンクすることはない。
    dotfilesDirOverride = builtins.getEnv "DOTFILES_DIR";
    workingDirectory = builtins.getEnv "PWD";
    dotfilesDir =
      if dotfilesDirOverride != ""
      then dotfilesDirOverride
      else workingDirectory;

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
    devPkgs = forAllSystems (system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # statixの現行nixpkgs derivationはsnapshot testだけが壊れているため、
        # Home Managerと同じ回避策を開発・静的解析環境にも適用する。
        overlays = [customOverlays.statix-no-check];
      });

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
      customOverlays.statix-no-check
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

    mkDarwinConfig = username:
      nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [./nix/darwin];
        specialArgs = {
          inherit inputs username;
        };
      };

    mkNixStaticCheck = system: let
      pkgs = devPkgs.${system};
    in
      pkgs.runCommand "nix-static-check" {
        nativeBuildInputs = with pkgs; [alejandra deadnix just statix];
        src = self;
      } ''
        export HOME="$TMPDIR"
        cp -r "$src" source
        chmod -R u+w source
        cd source
        just nix-fmt-check nix-lint nix-dead-code
        touch "$out"
      '';

    # Darwin専用オーバーレイ (ビルド修正)
    darwinOnlyOverlays = [
      customOverlays.cava-darwin-fix
      customOverlays.herdr-darwin-fix
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
    # `nix eval --json .#lib.hashUpdateManifest` で読み取り、汎用ループで照合する。
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
    # macOS (nix-darwin: システム設定 + Homebrew のみ)
    # ユーザー環境 (packages / dotfiles) は Linux と同じく standalone の
    # homeConfigurations で管理する。darwin-rebuild から分離することで、
    # Nix パッケージの日常更新に Homebrew の upgrade を巻き込まない。
    darwinConfigurations.${finalHostname} = mkDarwinConfig finalUsername;

    # home-manager設定
    homeConfigurations =
      {
        # CI用 (純粋評価、ビルドテスト用)
        "ci-linux" = mkCIConfig "x86_64-linux";
        "ci-darwin" = mkCIConfig "aarch64-darwin";
      }
      # 実際のユーザー用 (自動システム検出、--impure必須)。
      # `builtins.currentSystem` は impure 評価時のみ存在するため、`nix flake check`
      # などの pure 評価がこの属性を素通りするよう存在チェックで公開を絞る。
      // lib.optionalAttrs (builtins ? currentSystem) {
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
      };

    # `nix flake check`をHome Manager / nix-darwin / Nix静的解析の入口にする。
    checks = {
      x86_64-linux = {
        home = (mkCIConfig "x86_64-linux").activationPackage;
        nix-static = mkNixStaticCheck "x86_64-linux";
        # flake checkはdevShellを通常は評価するだけなので、checksからも参照して
        # CIで開発環境そのものをビルドする。
        dev-shell = self.devShells.x86_64-linux.default;
      };
      aarch64-darwin = {
        home = (mkCIConfig "aarch64-darwin").activationPackage;
        darwin = (mkDarwinConfig "ci").system;
        dev-shell = self.devShells.aarch64-darwin.default;
      };
    };

    # 開発シェル
    devShells = forAllSystems (system: let
      pkgs = devPkgs.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          neovim # Plugin smoke tests
          nil # Nix LSP
          nixd # Alternative Nix LSP
          alejandra # Nix formatter
          deadnix # Nix dead code finder
          just # Task runner
          statix # Nix linter
        ];
      };
    });

    # フォーマッター
    formatter = forAllSystems (system: (pkgsFor system).alejandra);

    # CIのhash検証用データ。標準のlib出力配下に置き、flake checkの
    # unknown-output警告を発生させない。
    lib = {inherit hashUpdateManifest;};
  };
}
