# Custom overlays for fixing build issues
{
  # Add termframe package (not in nixpkgs)
  termframe = final: prev: {
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
  cava-darwin-fix = final: prev: {
    iniparser = prev.iniparser.overrideAttrs (old: {
      # Skip tests to avoid building unity-test
      doCheck = false;
    });
  };

  # Fix git-graph build on aarch64-darwin
  # libz-sys crate can't find zlib.h
  git-graph-darwin-fix = final: prev: {
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
  jp2a-darwin-fix = final: prev: {
    jp2a = prev.jp2a.overrideAttrs (old: {
      meta = old.meta // {broken = false;};
    });
  };
}
