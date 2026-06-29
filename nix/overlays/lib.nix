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
    # "binary" | "tar" | "zip"。配布形式がプラットフォームで異なる場合は
    # system をキーにした attrset で指定できる (例: deck は darwin=zip / linux=tar)。
    format ? "binary",
    extraAttrs ? {},
    # CI の hash 更新方法。"prefetch" = artifact を nix-prefetch-url して算出 (既定)。
    # publisher が checksum を別途公開していて大容量 artifact の DL を避けたい場合に
    # 上書きする (例: claude-code は "manifest"、codex は "sha256sums")。pr.yml の
    # 汎用 update ループは "prefetch" のものだけを対象にし、それ以外は個別ステップで扱う。
    hashSource ? "prefetch",
  }: _final: prev: let
    inherit (prev.stdenv.hostPlatform) system;
    platform = platformMap.${system} or (throw "Unsupported system: ${system}");
    hash = hashes.${system} or (throw "No hash for system: ${system}");
    allPlatforms = builtins.attrNames platformMap;
    # format は文字列 (全プラットフォーム共通) か system キーの attrset (プラットフォーム別)
    resolvedFormat =
      if builtins.isAttrs format
      then format.${system} or (throw "No format for system: ${system}")
      else format;
    resolvedExtraAttrs =
      if builtins.isFunction extraAttrs
      then extraAttrs prev
      else extraAttrs;
    formatNativeBuildInputs =
      if resolvedFormat == "zip"
      then [prev.unzip]
      else [];
    # CI の hash 更新/検証用メタデータ。host system に依存せず platformMap 全体を
    # 走査するため、`nix eval .#hashUpdateManifest` から全プラットフォーム分の
    # (url, 現在 overlay に書かれている hash) を取り出せる。
    hashTargets = {
      inherit pname version hashSource;
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
        if resolvedFormat == "binary"
        then {dontUnpack = true;}
        else if resolvedFormat == "tar"
        then {}
        else if resolvedFormat == "zip"
        then {}
        else throw "mkBinaryRelease: unknown format \"${resolvedFormat}\" (expected \"binary\", \"tar\", or \"zip\")"
      )
      // {
        nativeBuildInputs = formatNativeBuildInputs ++ (resolvedExtraAttrs.nativeBuildInputs or []);

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp ${
            if resolvedFormat == "binary"
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
      // removeAttrs resolvedExtraAttrs ["nativeBuildInputs" "passthru"]);
  };
}
