{
  ruby-lsp = _final: prev: let
    gems = prev.bundlerEnv {
      name = "ruby-lsp-gems";
      inherit (prev) ruby;
      gemdir = ../ruby/ruby-lsp;
    };
    version = gems.gems.ruby-lsp.version;
  in {
    ruby-lsp = prev.stdenvNoCC.mkDerivation {
      pname = "ruby-lsp";
      inherit version;
      dontUnpack = true;
      nativeBuildInputs = [prev.makeWrapper prev.deno];
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/bin"
        makeWrapper ${prev.ruby}/bin/ruby "$out/bin/ruby-lsp" \
          --prefix GEM_PATH : ${gems}/${prev.ruby.gemPath} \
          --set BUNDLE_GEMFILE . \
          --add-flags ${gems}/${prev.ruby.gemPath}/gems/ruby-lsp-${version}/exe/ruby-lsp
        runHook postInstall
      '';
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        GEM_HOME=$TMPDIR/empty-gems GEM_PATH=$TMPDIR/empty-gems "$out/bin/ruby-lsp" --version | grep -Fx '${version}'
        deno run --allow-read --allow-write --allow-env --allow-run ${../../scripts/test-ruby-lsp.ts} "$out/bin/ruby-lsp" '${version}'
        runHook postInstallCheck
      '';
      passthru = {inherit gems;};
      meta = {
        description = "Ruby LSP with fixed Rails addon and RuboCop gems";
        homepage = "https://github.com/Shopify/ruby-lsp";
        license = prev.lib.licenses.mit;
        platforms = prev.ruby.meta.platforms;
      };
    };
  };
}
