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
}
