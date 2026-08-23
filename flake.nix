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

    cc-statusline = {
      url = "github:kokatsu/cc-statusline";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Renovate: datasource=github-releases depName=modem-dev/hunk
    hunk = {
      url = "github:modem-dev/hunk/v0.19.0";
      inputs.nixpkgs.follows = "nixpkgs";
      # bun2nix の既定 systems には、Nixpkgs 26.11 で削除された
      # x86_64-darwin が含まれる。実際に使用する3環境だけに限定する。
      inputs.bun2nix.inputs.systems.url = "github:nix-systems/triplet";
    };

    # Herdr 公式リリースバイナリ。nixpkgs 収録版より安定版への追従が速く、
    # Rust/Zig ツールチェーンを使ったソースビルドも不要。
    # 更新: nix flake update herdr-nix
    # https://github.com/herdrdev/herdr-nix
    herdr-nix = {
      url = "github:herdrdev/herdr-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # herdr の tab-numbers プラグイン。dotfiles から切り出した別リポジトリで、
    # herdr plugin link に実パスを渡す必要があるため flake ではなくソースとして取り込む
    # (pin を変えない限り store パスが変わらないので登録が陳腐化しない)。
    # 更新: nix flake update herdr-tab-numbers
    # https://github.com/kokatsu/herdr-tab-numbers
    herdr-tab-numbers = {
      url = "github:kokatsu/herdr-tab-numbers";
      flake = false;
    };

    # https://github.com/NousResearch/hermes-agent
    # Renovate: datasource=github-releases depName=NousResearch/hermes-agent
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.8.3";
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
        overlays = [
          # statixの現行nixpkgs derivationはsnapshot testだけが壊れているため、
          # Home Managerと同じ回避策を開発・静的解析環境にも適用する。
          customOverlays.statix-no-check
          # biomeはoverlayでリリースをpinしている。nixpkgs版とはバージョンが
          # ずれるため、devShell(=CIのlint job)でもoverlay版を使い、手元の
          # Home Manager profileと同じ整形結果になるようにする。
          customOverlays.biome
        ];
      });

    # 共通オーバーレイ (全プラットフォーム)
    commonOverlays = [
      # upstream overlay (pkgs.moonbit-bin.* を生やす)
      inputs.moonbit-overlay.overlays.default
      customOverlays.agent-browser
      customOverlays.biome
      customOverlays.cc-statusline
      customOverlays.claude-code
      customOverlays.codex
      customOverlays.cssmodules-language-server
      customOverlays.dcd
      customOverlays.deck-slides
      customOverlays.difftastic
      customOverlays.direnv-no-check
      customOverlays.git-graph-fork
      customOverlays.herdr
      customOverlays.hermes-agent
      customOverlays.kakehashi
      customOverlays.mise
      customOverlays.octorus
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
      customOverlays.jp2a-darwin-fix
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

    # home-manager設定 (実際のユーザー用。自動システム検出、--impure必須)。
    # `builtins.currentSystem` は impure 評価時のみ存在するため、`nix flake check`
    # などの pure 評価がこの属性を素通りするよう存在チェックで公開を絞る。
    # CI 用の設定はここではなく `checks.<system>.home` で公開する。system 名前空間を
    # 持たない homeConfigurations に置くと `nix flake check` が他 system 分まで強制
    # 評価し、catppuccin の IFD (importTOML) が異 platform のビルドを要求して落ちる。
    homeConfigurations = lib.optionalAttrs (builtins ? currentSystem) {
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
      # `just check-static` が必要とするツールを全て揃える。CI の lint job は
      # `nix develop --command just check-static` でこのシェルを使うため、
      # ここが手元と CI の lint ツールチェーンの single source of truth になる。
      default = pkgs.mkShell {
        packages = with pkgs; [
          neovim # Plugin smoke tests
          nil # Nix LSP
          nixd # Alternative Nix LSP
          just # Task runner
          git # just の _sh-files がファイル列挙に使う

          # Nix
          alejandra # Nix formatter
          deadnix # Nix dead code finder
          statix # Nix linter

          # Lua
          stylua # Lua formatter
          selene # Lua linter

          # Shell
          shellcheck # シェルスクリプト linter
          shfmt # シェルスクリプト formatter

          # Web / TypeScript
          biome # formatter + linter
          deno # fmt / lint / check

          # Markup / config
          markdownlint-cli # Markdown linter
          taplo # TOML formatter + linter
          yamlfmt # YAML formatter

          # Cross-cutting
          editorconfig-checker # EditorConfig 準拠チェッカー
          gitleaks # Secret detection and configuration smoke test
          typos # タイポ検出
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
