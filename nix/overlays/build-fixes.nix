let
  inherit (import ./lib.nix) guardEqual;
  # unstable更新で回避策が無条件に残らないよう、対象versionが変わった時点で
  # 評価を止めて「削除・更新・継続」の判断を必須にする。
  guardVersion = name: expected: package:
    guardEqual name expected (package.version or "unknown");
  guardedOverride = name: expected: package: override:
    guardVersion name expected package (package.overrideAttrs override);
in {
  # Pin vue-language-server to npm @vue/language-server 3.0.10.
  # vuejs/language-tools has no v3.0.10 Git tag, so use a minimal npm wrapper
  # package instead of the upstream monorepo build.
  vue-language-server-pin = _final: prev: let
    version = "3.0.10";
  in {
    vue-language-server = prev.buildNpmPackage {
      pname = "vue-language-server";
      inherit version;

      src = ../npm-locks/vue-language-server;

      npmDepsHash = "sha256-kYtpE97eFMRTvOGxKZMS4+epsTey0DFdL+qnHHPbAWE=";
      forceGitDeps = true;
      makeCacheWritable = true;
      dontNpmBuild = true;
      nativeBuildInputs = [prev.makeBinaryWrapper];

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib $out/bin
        cp -r node_modules $out/lib/node_modules
        rm -f $out/lib/node_modules/.package-lock.json
        makeWrapper ${prev.lib.getExe prev.nodejs} $out/bin/vue-language-server \
          --add-flags $out/lib/node_modules/@vue/language-server/bin/vue-language-server.js
        runHook postInstall
      '';

      meta =
        prev.vue-language-server.meta
        // {
          changelog = "https://github.com/vuejs/language-tools/releases";
        };
    };

    # 最新 (Vue 3 専用)。prev.vue-language-server は overlay 適用前の nixpkgs 素の値
    # なので、上書き前に別名 binary として退避し PATH 衝突を避ける。
    # Vue 3 プロジェクトの vue_ls の cmd から参照する。
    # 3.0.x を PATH 既定に残すのは、typescript-tools が PATH の vue-language-server から
    # @vue/typescript-plugin を解決しており、3.0.x の plugin だけが Vue 2/3 両対応のため。
    vue-language-server-latest = prev.writeShellScriptBin "vue-language-server-latest" ''
      exec ${prev.lib.getExe prev.vue-language-server} "$@"
    '';
  };

  # Use forked git-graph with:
  # - models read from ~/.config/git-graph on macOS too
  # - ANSI color wrapping fix (via forked gleisbau)
  # - --highlight-head to style the HEAD commit hash (via forked gleisbau)
  git-graph-fork = _final: prev: let
    forkedSrc = prev.fetchFromGitHub {
      owner = "kokatsu";
      repo = "git-graph";
      # branch: feat/highlight-head-cli
      rev = "e2f38a2b852d4a386f55735d2cfdf7e9240d1d76";
      hash = "sha256-/ZVZy4Ux6jUFMxIf+lSHY700do7h0lfx0iUOe9jSmzM=";
    };
  in {
    git-graph = guardedOverride "git-graph" "0.8.3" prev.git-graph (old: {
      src = forkedSrc;
      cargoDeps = prev.rustPlatform.fetchCargoVendor {
        inherit (old) pname;
        version = "fork";
        src = forkedSrc;
        hash = "sha256-8VOOd9GgnJ/VgiSJ2m9t0R4cj2s4MEDfGhLcHPBiRlU=";
      };
    });
  };

  # cargo-setup-hook が LIBGIT2_NO_VENDOR などを export し、vendored な C ライブラリを
  # 使えなくなった。上流の修正 (nixpkgs#586174, #585457) は version を変えないので、
  # 依存が既に入っているかで guard する。
  fff-nvim-libgit2 = _final: prev: let
    plugin = prev.vimPlugins.fff-nvim;
    fixedLib = plugin.fff-nvim-lib.overrideAttrs (old: {
      buildInputs = old.buildInputs ++ [prev.libgit2];
    });
    libgit2State =
      if builtins.elem prev.libgit2 plugin.fff-nvim-lib.buildInputs
      then "present"
      else "missing";
  in {
    vimPlugins = prev.vimPlugins.extend (_: _: {
      fff-nvim = guardEqual "fff-nvim libgit2" "missing" libgit2State (plugin.overrideAttrs (old: {
        postPatch = ''
          substituteInPlace lua/fff/download.lua \
            --replace-fail \
              "return plugin_dir .. '/../target/release'" \
              "return '${fixedLib}/lib'"
        '';
        passthru = old.passthru // {fff-nvim-lib = fixedLib;};
      }));
    });
  };

  # golden が GitHub の runner label 一覧を固定しており、2026-11-02 の macos-14 廃止で
  # TestLinterLintError が落ちる。2.5.0 で修正 (nixpkgs#585974)
  jactionlint-skip-runner-label-goldens = _final: prev: {
    jactionlint = guardedOverride "jactionlint" "2.4.0" prev.jactionlint (old: {
      checkFlags = [(builtins.head old.checkFlags + "|^TestLinterLintError$")];
    });
  };

  # # Fix jp2a build on darwin (marked as broken)
  # jp2a-darwin-fix = _final: prev: {
  #   jp2a = guardedOverride "jp2a" "1.3.3" prev.jp2a (old: {
  #     meta = old.meta // {broken = false;};
  #   });
  # };
}
