{inputs}: {
  pkl-neovim = _final: prev: {
    pkl-neovim = prev.stdenvNoCC.mkDerivation {
      pname = "pkl-neovim";
      version = builtins.substring 0 12 inputs.pkl-neovim.rev;
      src = inputs.pkl-neovim;
      dontConfigure = true;
      dontBuild = true;
      postPatch = ''
        substituteInPlace lua/pkl-neovim.lua \
          --replace-fail '  M.init_grammar()' '  vim.treesitter.language.register("pkl", "pcf")'
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R lua plugin ftdetect ftplugin queries snippets LICENSE.txt "$out/"
        runHook postInstall
      '';
    };
  };
  treesitter-nvim = _final: prev: let
    plugins = prev.vimPlugins.extend (_self: super: {
      nvim-treesitter = super.nvim-treesitter.overrideAttrs {
        name = "vimplugin-nvim-treesitter-${builtins.substring 0 12 inputs.nvim-treesitter.rev}";
        src = inputs.nvim-treesitter;
      };
    });
    treesitter =
      plugins.nvim-treesitter.withPlugins (grammars:
        with grammars; [bash css html javascript json lua markdown markdown_inline mermaid nix regex ruby rust scss sql svelte toml tsx typescript vim vue yaml pkl]);
    moonbitGrammar = prev.tree-sitter.buildGrammar {
      language = "moonbit";
      version = "0.1.0";
      src = inputs.moonbit-grammar;
    };
    moonbit = prev.runCommand "moonbit-neovim-grammar" {} ''
      mkdir -p "$out/parser" "$out/queries"
      ln -s ${moonbitGrammar}/parser "$out/parser/moonbit.so"
      ln -s ${inputs.moonbit-grammar}/queries "$out/queries/moonbit"
    '';
  in {
    treesitter-nvim = prev.symlinkJoin {
      name = "nvim-treesitter-with-grammars";
      paths = [treesitter moonbit] ++ treesitter.dependencies;
    };
  };
  lazy-nvim = _final: prev: {
    lazy-nvim = prev.vimPlugins.lazy-nvim.overrideAttrs {
      version = builtins.substring 0 12 inputs.lazy-nvim.rev;
      name = "vimplugin-lazy.nvim-${builtins.substring 0 12 inputs.lazy-nvim.rev}";
      src = inputs.lazy-nvim;
    };
  };
  peek-nvim = _final: prev: let
    revision = inputs.peek-nvim.rev;
    source = inputs.peek-nvim;
    denoDepsHash = "sha256-YL3ukQ2FpXC3XjClI6fT4KD4X4AA1enAw/l9ue9vPK4=";
    dependencies = (import ./fetch-deno-deps.nix {pkgs = prev;}) {
      pname = "peek";
      src = source;
      manifest = ../deno/peek/manifest.json;
      lockfile = ../deno/peek/deno.lock;
      hash = denoDepsHash;
    };
  in {
    peek-nvim = prev.stdenvNoCC.mkDerivation {
      pname = "peek.nvim";
      version = builtins.substring 0 12 revision;
      src = source;
      nativeBuildInputs = [prev.deno];
      dontConfigure = true;
      doCheck = true;
      checkPhase = ''
        runHook preCheck
        PEEK_TEST_SHELL=${prev.runtimeShell} deno run --allow-read --allow-write --allow-env \
          --allow-run --allow-net=localhost,127.0.0.1 ${../../scripts/test-peek.ts} "$PWD"
        runHook postCheck
      '';
      buildPhase = ''
        runHook preBuild
        export HOME=$TMPDIR/home
        export DENO_DIR=$TMPDIR/deno-cache
        mkdir -p "$HOME"
        cp -R ${dependencies}/vendor .
        chmod -R u+w vendor
        cp ${dependencies}/deno.lock deno.lock
        substituteInPlace vendor/deno.land/x/emit@0.38.1/emit.generated.js \
          --replace-fail 'new URL("emit_bg.wasm", import.meta.url)' 'new URL("file://${dependencies}/assets/emit_bg.wasm")'
        cp ${dependencies}/assets/*.css ${dependencies}/assets/*.js public/
        cp -R ${dependencies}/assets/fonts public/
        chmod -R u+w public
        deno run --config deno.json --vendor --cached-only --frozen-lockfile --no-check \
          --allow-read --allow-write --allow-env \
          ${../../scripts/build-peek.ts} ${dependencies}
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R lua public "$out/"
        cp LICENSE "$out/"
        cat > "$out/deno.json" <<EOF
        {"tasks":{"run":"${prev.deno}/bin/deno run --cached-only --no-remote --no-npm --allow-read --allow-write --allow-net --allow-env --allow-run --no-check public/main.bundle.js"}}
        EOF
        runHook postInstall
      '';
      passthru = {inherit dependencies revision;};
      meta = {
        description = "Markdown preview with Nix-built Deno bundles and assets";
        homepage = "https://github.com/kokatsu/peek.nvim";
        license = prev.lib.licenses.mit;
        platforms = prev.lib.platforms.unix;
      };
    };
  };
}
