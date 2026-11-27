{
  karabiner-config = _final: prev: let
    source = ../../karabiner-config;
    denoDepsHash = "sha256-creYNPpEdEb8NYLgrBIaGhYvnEulqO2jCb9DwUKO8so=";
    dependencies = (import ./fetch-deno-deps.nix {pkgs = prev;}) {
      pname = "karabiner";
      src = source;
      manifest = ../deno/karabiner/manifest.json;
      lockfile = ../../karabiner-config/deno.lock;
      hash = denoDepsHash;
    };
    stub = ''{"profiles":[{"name":"Default","selected":true}]}'';
    run = "deno run --config deno.json --vendor --cached-only --frozen-lockfile --node-modules-dir=manual --allow-env --allow-read --allow-write --allow-sys=homedir ./karabiner.ts";
  in {
    karabiner-config = prev.stdenvNoCC.mkDerivation {
      pname = "karabiner-config";
      version = "1";
      src = source;
      nativeBuildInputs = [prev.deno prev.jq];
      dontConfigure = true;
      doCheck = true;
      checkPhase = ''
        runHook preCheck
        bash ${../../scripts/test-karabiner-profile.sh} "$PWD/profile.json" ${../../scripts/apply-karabiner-profile.sh}
        # --dry-run は karabiner.json を書き換えない
        echo '${stub}' > "$HOME/.config/karabiner/karabiner.json"
        ${run} --dry-run > /dev/null
        echo '${stub}' | cmp - "$HOME/.config/karabiner/karabiner.json"
        runHook postCheck
      '';
      buildPhase = ''
        runHook preBuild
        export HOME=$TMPDIR/home
        export DENO_DIR=$TMPDIR/deno-cache
        mkdir -p "$HOME/.config/karabiner"
        echo '${stub}' > "$HOME/.config/karabiner/karabiner.json"
        cp -R ${dependencies}/vendor ${dependencies}/node_modules .
        jq '.nodeModulesDir = "manual" | .vendor = true' ${dependencies}/config.json > deno.json
        ${run}
        jq '.profiles[0] | del(.name, .selected)' "$HOME/.config/karabiner/karabiner.json" > profile.json
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp profile.json "$out/"
        runHook postInstall
      '';
      passthru = {inherit dependencies;};
      meta = {
        description = "Generated Default profile modifications for Karabiner";
        license = prev.lib.licenses.mit;
        platforms = prev.lib.platforms.unix;
      };
    };
  };
}
