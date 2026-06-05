{
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
    iniparser = prev.iniparser.overrideAttrs (_old: {
      doCheck = false;
    });
  };

  # direnv 2.37.1 zsh checkPhase hangs on macOS Nix sandbox
  # (SIGCHLD race in waitforpid during $(direnv export zsh))
  direnv-no-check = _final: prev: {
    direnv = prev.direnv.overrideAttrs (_old: {
      doCheck = false;
    });
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
    git-graph = prev.git-graph.overrideAttrs (old: {
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

  # pipx 1.8.0 test_package_specifier tests fail with newer `packaging`,
  # which normalizes PEP 508 direct references to `name @ url` (space around
  # `@`) while the tests still assert the old `name@ url` form. Test-only
  # formatting drift; pipx itself works fine. Disable via pythonPackagesExtensions
  # because top-level `pipx` is `toPythonApplication python3Packages.pipx`,
  # and the tests run through pytestCheckHook (not the `doCheck` gate).
  pipx-no-check = _final: prev: {
    pythonPackagesExtensions =
      (prev.pythonPackagesExtensions or [])
      ++ [
        (_pyfinal: pyprev: {
          pipx = pyprev.pipx.overrideAttrs (old: {
            disabledTests =
              (old.disabledTests or [])
              ++ [
                "test_fix_package_name"
                "test_parse_specifier_for_metadata"
              ];
          });
        })
      ];
  };

  # Fix jp2a build on darwin (marked as broken)
  jp2a-darwin-fix = _final: prev: {
    jp2a = prev.jp2a.overrideAttrs (old: {
      meta = old.meta // {broken = false;};
    });
  };

  # Fix LDC on macOS 26+ (Darwin 25+)
  # The ldc2.conf references a non-existent compiler-rt directory
  # and the target triple conflicts with Nix cc-wrapper
  ldc-darwin-fix = _final: prev: {
    ldc = prev.ldc.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + prev.lib.optionalString prev.stdenv.hostPlatform.isDarwin ''
          # Remove non-existent compiler-rt directory from lib-dirs
          if [ -f "$out/etc/ldc2.conf" ]; then
            sed -i.bak 's|"[^"]*lib/clang/[0-9]*/lib/darwin".*||' "$out/etc/ldc2.conf"
          fi
        '';
    });
  };
}
