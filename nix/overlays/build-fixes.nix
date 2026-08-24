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
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/vue-language-server/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/vue-language-server/package-lock.json);
  in {
    vue-language-server = prev.buildNpmPackage {
      pname = "vue-language-server";
      inherit version;

      src = prev.runCommand "vue-language-server-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-HL5zSw7MP+sEv3ILDPJ53hPqXlMggRlLufaXqYgF4s8=";
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

  # Fix cava build on aarch64-darwin
  # iniparser's dependency unity-test has C++ compilation issues with new clang
  cava-darwin-fix = _final: prev: {
    iniparser = guardedOverride "iniparser" "4.2.6" prev.iniparser (_old: {
      doCheck = false;
    });
  };

  # direnv 2.37.1 zsh checkPhase hangs on macOS Nix sandbox
  # (SIGCHLD race in waitforpid during $(direnv export zsh))
  direnv-no-check = _final: prev: {
    direnv =
      if prev.stdenv.hostPlatform.isDarwin
      then guardedOverride "direnv" "2.37.1" prev.direnv (_old: {doCheck = false;})
      else prev.direnv;
  };

  # Use forked git-graph with:
  # - --current option
  # - ANSI color wrapping fix
  # - HEAD highlight feature
  # - Performance optimizations for graph construction
  # Also fixes build on aarch64-darwin (libz-sys crate can't find zlib.h)
  git-graph-fork = _final: prev: let
    forkedSrc = prev.fetchFromGitHub {
      owner = "kokatsu";
      repo = "git-graph";
      # branch: perf/optimize-graph-construction
      rev = "2781f5305c8d46c6dda0e7c71d4238954887f5d9";
      hash = "sha256-i1E6Rxc+LqEetSqlhrHciybm+DQIAYeJfzWGO87G5+I=";
    };
  in {
    git-graph = guardedOverride "git-graph" "0.8.0" prev.git-graph (old: {
      src = forkedSrc;
      cargoDeps = prev.rustPlatform.fetchCargoVendor {
        inherit (old) pname;
        version = "fork";
        src = forkedSrc;
        hash = "sha256-a7Jo/kHuQH7OQrzAMY63jFEOPfnYKAb4AW65V5BEfWM=";
      };
      meta = old.meta // {broken = false;};
      buildInputs = (old.buildInputs or []) ++ [prev.zlib];
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.pkg-config];
      LIBZ_SYS_STATIC = "0";
      PKG_CONFIG_PATH = "${prev.zlib.dev}/lib/pkgconfig";
    });
  };

  # statix 0.5.8-unstable-2026-07-17 fails its insta snapshot test
  # (redundant_pattern_bind fix output drifted from the recorded snapshot;
  # upstream issue oppiliappan/statix#64). Test-only drift; the linter works.
  statix-no-check = _final: prev: {
    statix = guardedOverride "statix" "0.5.8-unstable-2026-07-17" prev.statix (_old: {
      doCheck = false;
    });
  };

  # Fix jp2a build on darwin (marked as broken)
  jp2a-darwin-fix = _final: prev: {
    jp2a = guardedOverride "jp2a" "1.3.3" prev.jp2a (old: {
      meta = old.meta // {broken = false;};
    });
  };

  # vscode-langservers-extracted 4.10.0 の各サーバ bundle は esbuild が生成した
  # `createRequire(import.meta.url)` を含む。これは CJS では無効な import.meta 構文で、
  # Node 24 のモジュール構文自動判定が CJS ファイルを ESM と誤認し、先頭の require() が
  # "require is not defined in ES module scope" でクラッシュする (jsonls/cssls/htmlls 全滅)。
  # import.meta.{url,dirname} を CJS 等価の __filename/__dirname に置換して解消する。
  vscode-langservers-detect-module-fix = _final: prev: {
    vscode-langservers-extracted = guardedOverride "vscode-langservers-extracted" "1.126.04524" prev.vscode-langservers-extracted (old: {
      postInstall =
        (old.postInstall or "")
        + ''
          find $out -path '*/node/*ServerMain.js' \
            -exec sed -i \
              -e 's|import\.meta\.url|__filename|g' \
              -e 's|import\.meta\.dirname|__dirname|g' {} +
        '';
    });
  };

  # Fix a whole-server crash in tmux. tty_keys_next() dereferences
  # c->session->curw->window when handling a FocusIn/FocusOut escape sequence,
  # with no NULL guard on c->session. If a focus event arrives while the client
  # has no current session (e.g. mid-detach, with focus-events + destroy-unattached),
  # the server segfaults and every session dies. Unfixed upstream as of 3.7c.
  tmux-focus-crash-fix = _final: prev: {
    tmux = guardedOverride "tmux" "3.7c" prev.tmux (old: {
      patches = (old.patches or []) ++ [./tmux-focus-null-guard.patch];
    });
  };
}
