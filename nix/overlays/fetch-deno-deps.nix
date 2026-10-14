{pkgs}: {
  pname,
  src,
  manifest,
  lockfile,
  hash,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "${pname}-deno-deps";
  version = "1";
  inherit src;
  nativeBuildInputs = [pkgs.deno pkgs.cacert];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR/home
    export DENO_DIR=$TMPDIR/deno-cache
    export DENO_DEPS_FROZEN=1
    mkdir -p "$HOME"
    cp ${lockfile} deno.lock
    deno run --allow-all ${../../scripts/fetch-deno-deps.ts} ${manifest} "$out"
    runHook postBuild
  '';
  dontInstall = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = hash;
}
