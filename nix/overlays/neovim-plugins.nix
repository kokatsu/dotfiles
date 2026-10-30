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
  treesitter-nvim = final: prev: let
    inherit (prev.vimPlugins) nvim-treesitter;
    treesitter =
      nvim-treesitter.withPlugins (grammars:
        with grammars; [bash css html javascript json lua markdown markdown_inline mermaid nix regex ruby rust scss sql svelte toml tsx typescript vim vue yaml pkl]);
    kakehashiExtra =
      nvim-treesitter.withPlugins (grammars:
        with grammars; [c d diff gitignore go ini json5 latex make pascal perl po powershell python r typst xml zig]);
    kakehashiQueries = prev.runCommand "kakehashi-queries" {nativeBuildInputs = [prev.python3];} ''
      mkdir -p "$out"
      cp -R ${nvim-treesitter.src}/runtime/queries "$out/queries"
      chmod -R u+w "$out/queries"
      # kakehashi 1.0.0 rejects capture-valued URL metadata in Neovim queries.
      python3 - "$out/queries" <<'PY'
      import pathlib
      import re
      import sys

      queries = pathlib.Path(sys.argv[1])
      pattern = re.compile(r'\(#set! @[\w.]+ url @[\w.]+\)')
      changes = []
      for path in queries.glob('*/highlights.scm'):
          original = path.read_text()
          updated, count = pattern.subn("", original)
          if count:
              changes.append((path, updated, count))
      assert sum(count for _, _, count in changes) == 8, 'URL metadata changed upstream'
      for path, updated, _ in changes:
          path.write_text(updated)
          assert not pattern.search(path.read_text()), path
      PY
    '';
    tmuxGrammar = prev.tree-sitter.buildGrammar {
      language = "tmux";
      version = "${(builtins.fromJSON (builtins.readFile "${inputs.tmux-grammar}/tree-sitter.json")).metadata.version}+rev=${builtins.substring 0 12 inputs.tmux-grammar.rev}";
      src = inputs.tmux-grammar;
      generate = true;
    };
    tmux = prev.runCommand "tmux-kakehashi-grammar" {} ''
      mkdir -p "$out/parser" "$out/queries"
      ln -s ${tmuxGrammar}/parser "$out/parser/tmux.so"
      ln -s ${inputs.tmux-grammar}/queries "$out/queries/tmux"
    '';
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
    kakehashi-grammars = prev.symlinkJoin {
      name = "kakehashi-grammars";
      paths = [kakehashiQueries final.treesitter-nvim tmux] ++ kakehashiExtra.dependencies;
    };
    kakehashi-config = (prev.formats.toml {}).generate "kakehashi.toml" {
      searchPaths = ["${final.kakehashi-grammars}"];
      languages._.autoInstall = false;
    };
  };
  lazy-nvim = _final: prev: {
    lazy-nvim = prev.vimPlugins.lazy-nvim.overrideAttrs (old: {
      version = builtins.substring 0 12 inputs.lazy-nvim.rev;
      name = "vimplugin-lazy.nvim-${builtins.substring 0 12 inputs.lazy-nvim.rev}";
      src = inputs.lazy-nvim;
      # Nix が生成した help tags は store 内にあり、restore 時に再生成できない。
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace lua/lazy/manage/task/plugin.lua \
            --replace-fail 'return not plugin._.is_local and not plugin._.dirty' \
              'return plugin._.is_local or not plugin._.dirty'
        '';
    });
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
