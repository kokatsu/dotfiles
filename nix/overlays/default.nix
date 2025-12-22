# Custom overlays for fixing build issues
{
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
}
