# 公式のソースビルドに prefix バーとフォーカス枠の描画パッチ、シェル補完を追加する。
{inputs}: {
  herdr = _final: prev: let
    upstream = inputs.herdr-src.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          ./patches/herdr-prefix-bar.patch
          ./patches/herdr-heavy-focus-border.patch
          # 上流の symbols は × などの小さな Unicode 記号で、PlemolJP では
          # セル幅いっぱいの Nerd Font アイコンより明らかに小さく見分けにくい
          ./patches/herdr-nerd-status-icons.patch
          # herdr-nvim のサイドバーを最初から目的の幅で開くため。
          # 上流の提案: https://github.com/herdrdev/herdr/discussions/3541
          ./patches/herdr-plugin-pane-ratio.patch
        ];
    });
  in {
    herdr = prev.symlinkJoin {
      name = "herdr-${upstream.version}";
      pname = "herdr";
      inherit (upstream) version;
      paths = [upstream];
      nativeBuildInputs = [prev.installShellFiles];
      postBuild =
        prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform)
        # bash
        ''
          completionDir=$(mktemp -d)

          generateCompletion() {
            shell=$1
            output=$2
            if ! "$out/bin/herdr" completion "$shell" >"$output"; then
              echo "herdr completion $shell failed" >&2
              return 1
            fi
            if [[ ! -s "$output" ]]; then
              echo "herdr completion $shell produced empty output" >&2
              return 1
            fi
          }

          generateCompletion bash "$completionDir/herdr.bash"
          generateCompletion fish "$completionDir/herdr.fish"
          generateCompletion zsh "$completionDir/_herdr"

          installShellCompletion --cmd herdr \
            --bash "$completionDir/herdr.bash" \
            --fish "$completionDir/herdr.fish" \
            --zsh "$completionDir/_herdr"
        '';
      inherit (upstream) meta;
      passthru = (upstream.passthru or {}) // {unwrapped = upstream;};
    };
  };

  # $out をそのまま herdr plugin link に渡すので、上流の plugin root と同じく
  # herdr-plugin.toml・lua/・bin/herdr-nvim を同じ階層に置く。lua/ は daemon が
  # bin/herdr-nvim から親を辿って探し、nvim の runtimepath に注入する。
  # manifest の [[build]] (バイナリを取得する install.sh) は herdr plugin link では実行されない
  herdr-nvim = _final: prev: let
    src = inputs.herdr-nvim-src;
  in {
    herdr-nvim = prev.rustPlatform.buildRustPackage {
      pname = "herdr-nvim";
      inherit ((prev.lib.importTOML "${src}/Cargo.toml").package) version;
      inherit src;

      cargoLock.lockFile = "${src}/Cargo.lock";

      # サイドバーはエージェントではなくプラグインのペインなので、上流の
      # `herdr agent focus` は agent_not_found で失敗し、リンクのクリックで
      # ファイルを開いてもフォーカスがサイドバーへ移らない
      patches = [
        ./patches/herdr-nvim-focus-plugin-pane.patch
        # 上流は幅を設定できず、サイドバーは herdr 既定の 50% で開く。
        # herdr 側の herdr-plugin-pane-ratio.patch が前提
        ./patches/herdr-nvim-sidebar-width.patch
      ];

      nativeCheckInputs = [prev.git];
      # ソースを git チェックアウトとして git ls-files で索引するテスト。
      # flake input のソースには .git がないので通らない
      checkFlags = ["--skip=picker::tests::fff_end_to_end_over_this_repo"];

      # doc/ は fixup が share/doc へ移して runtimepath から外れるので入れない
      postInstall = ''
        cp -r herdr-plugin.toml lua plugin $out/
      '';

      meta = with prev.lib; {
        description = "Neovim sidebar and agent annotations for herdr";
        homepage = "https://github.com/ChmaraX/herdr-nvim";
        license = licenses.mit;
        mainProgram = "herdr-nvim";
      };
    };
  };
}
