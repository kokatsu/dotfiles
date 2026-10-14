{inputs}: {
  zeno-zsh = _final: prev: let
    denoDepsHash = "sha256-C+iys/I1V0Xu3rSA0F3r6lWgulokuMf0Hkt0UR0g2LA=";
    dependencies = (import ./fetch-deno-deps.nix {pkgs = prev;}) {
      pname = "zeno";
      src = inputs.zeno-zsh;
      manifest = ../deno/zeno/manifest.json;
      lockfile = ../deno/zeno/deno.lock;
      hash = denoDepsHash;
    };
  in {
    zeno-zsh = prev.stdenvNoCC.mkDerivation {
      pname = "zeno.zsh";
      version = builtins.substring 0 12 inputs.zeno-zsh.rev;
      src = inputs.zeno-zsh;
      nativeBuildInputs = [prev.jq prev.zsh prev.deno];
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        DENO_SQLITE_PATH=${prev.sqlite.out}/lib/libsqlite3${prev.stdenv.hostPlatform.extensions.sharedLibrary} \
          deno run --allow-all ${../../scripts/test-zeno.ts} "$out"
        runHook postInstallCheck
      '';
      dontConfigure = true;
      dontBuild = true;
      postPatch = ''
        sh ${../../scripts/prepare-zeno} "$PWD"
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R . "$out/"
        cp -R ${dependencies}/vendor ${dependencies}/node_modules "$out/"
        cp ${dependencies}/deno.lock "$out/deno.lock"
        jq '.nodeModulesDir = "manual" | .vendor = true' ${dependencies}/config.json > "$out/deno.json"
        substituteInPlace "$out/bin/zeno" "$out/bin/zeno-history-client" \
          --replace-fail '#!/usr/bin/env zsh' '#!${prev.zsh}/bin/zsh'
        substituteInPlace "$out/bin/zeno" \
          --replace-fail 'args=("$@")' 'export ZENO_ROOT='"$out"'; args=("$@")' \
          --replace-fail '--node-modules-dir=auto' '--node-modules-dir=manual' \
          --replace-fail 'exec deno run' 'export DENO_SQLITE_PATH=${prev.sqlite.out}/lib/libsqlite3${prev.stdenv.hostPlatform.extensions.sharedLibrary}; exec ${prev.deno}/bin/deno run --config "$ZENO_ROOT/deno.json" --vendor --cached-only --frozen-lockfile'
        cat > "$out/bin/zeno-server" <<EOF
        #!${prev.zsh}/bin/zsh
        export DENO_SQLITE_PATH=${prev.sqlite.out}/lib/libsqlite3${prev.stdenv.hostPlatform.extensions.sharedLibrary}
        exec ${prev.deno}/bin/deno run --config "$out/deno.json" --vendor --cached-only --frozen-lockfile --node-modules-dir=manual --no-check --allow-env --allow-read --allow-run --allow-write --allow-ffi --allow-net "$out/src/server.ts" "\$@"
        EOF
        cat > "$out/shells/zsh/functions/zeno" <<'EOF'
        #autoload
        command "$ZENO_ROOT/bin/zeno" "$@"
        EOF
        cat > "$out/shells/zsh/functions/zeno-server" <<'EOF'
        #autoload
        command "$ZENO_ROOT/bin/zeno-server" "$@"
        EOF
        runHook postInstall
      '';
      passthru = {inherit dependencies;};
      meta = {
        description = "Zsh completion and history with fixed offline Deno dependencies";
        homepage = "https://github.com/yuki-yano/zeno.zsh";
        license = prev.lib.licenses.mit;
        platforms = prev.lib.platforms.unix;
      };
    };
  };
}
