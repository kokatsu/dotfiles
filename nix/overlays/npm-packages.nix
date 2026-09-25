{
  # vite-plus - Unified toolchain for the web (vp CLI)
  # vite-plus's tarball references private workspace packages in its own
  # devDependencies, so we cannot reuse its package.json directly. Instead we
  # vendor a minimal wrapper package.json + package-lock.json that depends on
  # vite-plus@<version>, then expose node_modules/vite-plus/bin/vp as $out/bin/vp.
  # Renovate: datasource=npm depName=vite-plus
  vite-plus = _final: prev: let
    version = "0.3.3";
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/vite-plus/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/vite-plus/package-lock.json);
  in {
    vite-plus = prev.buildNpmPackage {
      pname = "vite-plus";
      inherit version;

      src = prev.runCommand "vite-plus-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-qrieJ8j7Km4CZijn46HY5y5LpvTIYZQtthcgs9/lylw=";
      npmFlags = ["--legacy-peer-deps"];
      dontNpmBuild = true;

      # Hoisted dependencies must not sit at lib/node_modules top level, or
      # they collide with other npm packages in Home Manager's buildEnv (e.g.
      # estree-walker vs vue-language-server). Nest them under vite-plus's own
      # node_modules instead; Node resolves them there first.
      installPhase = ''
        runHook preInstall
        dest=$out/lib/node_modules/vite-plus
        mkdir -p "$(dirname "$dest")" $out/bin
        mv node_modules/vite-plus "$dest"
        mv node_modules "$dest/node_modules"
        for bin in vp vpr; do
          ln -sfn ../../bin/$bin "$dest/node_modules/.bin/$bin"
          ln -s ../lib/node_modules/vite-plus/bin/$bin $out/bin/$bin
        done
        runHook postInstall
      '';

      # `vp create` copies its scaffold templates with fs.copyFileSync, which
      # preserves the source mode. Sourced from the read-only Nix store, every
      # generated file lands as 0444, so vp's own follow-up edit of package.json
      # fails with EACCES. Make copy() restore a writable mode on the output.
      postInstall = ''
        substituteInPlace $out/lib/node_modules/vite-plus/dist/create/bin.js \
          --replace-fail 'else fs.copyFileSync(src, dest);' \
            'else { fs.copyFileSync(src, dest); fs.chmodSync(dest, 0o644); }'
      '';

      meta = with prev.lib; {
        description = "The Unified Toolchain for the Web";
        homepage = "https://github.com/voidzero-dev/vite-plus";
        license = licenses.mit;
        mainProgram = "vp";
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
      };
    };
  };

  # textlint-rule-preset-ai-writing - AI が生成した文章パターンを検出する textlint プリセット。
  # nixpkgs 未収録。旧名 `textlint-rule-preset-ai-writing` は npm 1.1.0 で凍結され、現行は
  # スコープ付き `@textlint-ja/textlint-rule-preset-ai-writing` で配布されている。vite-plus と
  # 同じく wrapper package.json で npm tarball を取り込み、prebuilt な lib/ をそのまま使う
  # (ソースは lib/ を含まず prepare で git config を呼ぶためビルドしない)。依存はルール本体の
  # node_modules にネストし、textlint-with-rules の symlinkJoin で @textlint 等が衝突しないようにする。
  # Renovate: datasource=npm depName=@textlint-ja/textlint-rule-preset-ai-writing
  textlint-rule-preset-ai-writing = _final: prev: let
    version = "1.7.0";
    packageJson = prev.writeText "package.json" (builtins.readFile ../npm-locks/textlint-rule-preset-ai-writing/package.json);
    packageLock = prev.writeText "package-lock.json" (builtins.readFile ../npm-locks/textlint-rule-preset-ai-writing/package-lock.json);
  in {
    textlint-rule-preset-ai-writing = prev.buildNpmPackage {
      pname = "textlint-rule-preset-ai-writing";
      inherit version;

      src = prev.runCommand "textlint-rule-preset-ai-writing-src" {} ''
        mkdir -p $out
        cp ${packageJson} $out/package.json
        cp ${packageLock} $out/package-lock.json
      '';

      npmDepsHash = "sha256-Sv4t7GR8SJpbfiEGX5TxduWG8zI6HBOnHMmIMgTPTXg=";
      dontNpmBuild = true;

      # nixpkgs の textlint ルールパッケージと同じ構造にする:
      # トップレベルにはルール本体 (@textlint-ja/...) のみを公開し、依存はその
      # node_modules にネストする。これで textlint の symlinkJoin 時に衝突しない。
      installPhase = ''
        runHook preInstall
        dest=$out/lib/node_modules/@textlint-ja/textlint-rule-preset-ai-writing
        mkdir -p "$(dirname "$dest")"
        mv node_modules/@textlint-ja/textlint-rule-preset-ai-writing "$dest"
        rmdir node_modules/@textlint-ja 2>/dev/null || true
        mv node_modules "$dest/node_modules"
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "Textlint preset to detect AI-generated writing patterns in Japanese";
        homepage = "https://github.com/textlint-ja/textlint-rule-preset-ai-writing";
        license = licenses.mit;
        platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
      };
    };
  };

  # textlint-with-rules - textlint 本体と日本語校正ルールを 1 つの derivation にまとめる。
  # ルールは NODE_PATH 経由でしか解決されないため、本体と同じ closure に同居させないと
  # 見つからない。Home Manager の packages と開発シェルの双方が同じ構成を参照できるよう、
  # packages.nix に直書きせず overlay に置く。
  textlint-with-rules = final: prev: {
    textlint-with-rules = prev.symlinkJoin {
      name = "textlint-with-rules";
      paths = [
        prev.textlint
        prev.textlint-rule-preset-ja-technical-writing
        prev.textlint-rule-prh
        prev.textlint-rule-terminology
        final.textlint-rule-preset-ai-writing
        # Keep the local filter on NODE_PATH, like the other textlint rules.
        (prev.writeTextDir "lib/node_modules/textlint-filter-rule-quotes/index.js"
          (builtins.readFile ../../.config/claude/hooks/textlint-filter-quotes.cjs))
      ];
      nativeBuildInputs = [prev.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/textlint \
          --set NODE_PATH "$out/lib/node_modules"
      '';
    };
  };
}
