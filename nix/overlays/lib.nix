{
  mkBinaryRelease = {
    pname,
    version,
    hashes,
    platformMap,
    url,
    meta,
    binName ? pname,
    binPath ? binName,
    format ? "binary",
    extraAttrs ? {},
  }: _final: prev: let
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
    allPlatforms = builtins.attrNames platformMap;
    resolvedExtraAttrs =
      if builtins.isFunction extraAttrs
      then extraAttrs prev
      else extraAttrs;
    formatNativeBuildInputs =
      if format == "zip"
      then [prev.unzip]
      else [];
    # CI の hash 更新/検証用メタデータ。host system に依存せず platformMap 全体を
    # 走査するため、`nix eval .#hashUpdateManifest` から全プラットフォーム分の
    # (url, 現在 overlay に書かれている hash) を取り出せる。
    hashTargets = {
      inherit pname version;
      targets =
        builtins.mapAttrs (sys: plat: {
          url = url plat;
          hash = hashes.${sys} or null;
        })
        platformMap;
    };
  in {
    ${pname} = prev.stdenvNoCC.mkDerivation ({
        inherit pname;
        inherit version;

        src = prev.fetchurl {
          url = url platform;
          inherit hash;
        };
      }
      // (
        # "binary": single prebuilt binary, no unpack
        # "tar":    tar archive (.tar.gz / .tar.xz) unpacked by stdenv default;
        #           caller sets sourceRoot / extraAttrs as needed
        # "zip":    zip archive unpacked by stdenv default.
        if format == "binary"
        then {dontUnpack = true;}
        else if format == "tar"
        then {}
        else if format == "zip"
        then {}
        else throw "mkBinaryRelease: unknown format \"${format}\" (expected \"binary\", \"tar\", or \"zip\")"
      )
      // {
        nativeBuildInputs = formatNativeBuildInputs ++ (resolvedExtraAttrs.nativeBuildInputs or []);

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp ${
            if format == "binary"
            then "$src"
            else binPath
          } $out/bin/${binName}
          chmod +x $out/bin/${binName}
          runHook postInstall
        '';

        meta = with prev.lib; {
          inherit (meta) description homepage;
          license =
            if meta ? license
            then licenses.${meta.license}
            else licenses.mit;
          platforms = meta.platforms or allPlatforms;
          mainProgram = meta.mainProgram or binName;
        };

        passthru = (resolvedExtraAttrs.passthru or {}) // {inherit hashTargets;};
      }
      // builtins.removeAttrs resolvedExtraAttrs ["nativeBuildInputs" "passthru"]);
  };
}
