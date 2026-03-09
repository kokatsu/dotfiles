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
        if format == "binary"
        then {dontUnpack = true;}
        else if format == "tgz"
        then {
          unpackPhase = ''
            runHook preUnpack
            mkdir -p source
            tar -xzf $src -C source --strip-components=1
            runHook postUnpack
          '';
        }
        else {}
      )
      // {
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
      }
      // extraAttrs);
  };

  mkVendoredNpmPackage = {
    pname,
    version,
    npmDepsHash,
    lockDir ? pname,
    meta,
    tarball ? null,
    extraAttrs ? {},
  }: _final: prev: let
    lockPath = ../npm-locks/${lockDir};
    packageLock = prev.writeText "package-lock.json" (builtins.readFile (lockPath + "/package-lock.json"));
  in {
    ${pname} = prev.buildNpmPackage ({
        inherit pname version npmDepsHash;

        src =
          if tarball != null
          then
            prev.runCommand "${pname}-src" {} ''
              mkdir -p $out
              tar -xzf ${tarball} -C $out --strip-components=1
              cp ${packageLock} $out/package-lock.json
            ''
          else let
            packageJson = prev.writeText "package.json" (builtins.readFile (lockPath + "/package.json"));
          in
            prev.runCommand "${pname}-src" {} ''
              mkdir -p $out
              cp ${packageJson} $out/package.json
              cp ${packageLock} $out/package-lock.json
            '';

        dontNpmBuild = true;

        meta = with prev.lib; {
          inherit (meta) description homepage;
          license =
            if meta ? license
            then licenses.${meta.license}
            else licenses.mit;
          mainProgram = meta.mainProgram or pname;
        };
      }
      // extraAttrs);
  };
}
