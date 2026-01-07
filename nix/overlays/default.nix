# Custom overlays for fixing build issues
{
  # Pin vue-language-server to 3.0.8
  vue-language-server-pin = _final: prev: {
    vue-language-server = prev.vue-language-server.overrideAttrs (old: rec {
      version = "3.0.8";
      src = prev.fetchFromGitHub {
        owner = "vuejs";
        repo = "language-tools";
        rev = "v${version}";
        hash = "sha256-bUy1H481oxoddprj4WJaZdwbQA6a3SaJ92I/PJubltc=";
      };
      pnpmDeps = prev.fetchPnpmDeps {
        inherit (old) pname;
        inherit version src;
        fetcherVersion = 1;
        hash = "sha256-0H7j/TlVTkQ5dGlm1AgvtXYa+pPnkvadlNGygEaB85k=";
      };
    });
  };
  # Add termframe package (not in nixpkgs)
  termframe = _final: prev: {
    termframe = prev.rustPlatform.buildRustPackage rec {
      pname = "termframe";
      version = "0.7.4";

      src = prev.fetchFromGitHub {
        owner = "pamburus";
        repo = "termframe";
        rev = "v${version}";
        hash = "sha256-jAcutfzHYLPTF37dZo9gbGQ9WjIxqsYq2RONZP+xsUo=";
      };

      cargoHash = "sha256-7KUG9qsMtm9utF7w6PQkCfjw0HVCXnZ0tMHprp+cS3o=";

      nativeBuildInputs = [prev.pkg-config];
      buildInputs = prev.lib.optionals prev.stdenv.hostPlatform.isDarwin [
        prev.libiconv
      ];

      meta = with prev.lib; {
        description = "Terminal output SVG screenshot tool";
        homepage = "https://github.com/pamburus/termframe";
        license = licenses.mit;
        maintainers = [];
      };
    };
  };

  # Fix cava build on aarch64-darwin
  # iniparser's dependency unity-test has C++ compilation issues with new clang
  cava-darwin-fix = _final: prev: {
    iniparser = prev.iniparser.overrideAttrs (_old: {
      # Skip tests to avoid building unity-test
      doCheck = false;
    });
  };

  # Fix git-graph build on aarch64-darwin
  # libz-sys crate can't find zlib.h
  git-graph-darwin-fix = _final: prev: {
    git-graph = prev.git-graph.overrideAttrs (old: {
      # Mark as not broken
      meta = old.meta // {broken = false;};
      # Add zlib to build inputs
      buildInputs = (old.buildInputs or []) ++ [prev.zlib];
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.pkg-config];
      # Set environment variables for zlib
      LIBZ_SYS_STATIC = "0";
      PKG_CONFIG_PATH = "${prev.zlib.dev}/lib/pkgconfig";
    });
  };

  # Fix jp2a build on darwin (marked as broken)
  jp2a-darwin-fix = _final: prev: {
    jp2a = prev.jp2a.overrideAttrs (old: {
      meta = old.meta // {broken = false;};
    });
  };
}
