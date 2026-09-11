let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
  # 実際に使う 3 環境のみ (x86_64-darwin は不使用)
  appleGnuPlatformMap = {
    "aarch64-darwin" = "aarch64-apple-darwin";
    "aarch64-linux" = "aarch64-unknown-linux-gnu";
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
  };
in {
  # mise - dev tools, env vars, task runner
  # Renovate: datasource=github-releases depName=jdx/mise
  mise = mkBinaryRelease rec {
    pname = "mise";
    version = "2026.8.12";
    hashes = {
      "aarch64-darwin" = "sha256-kpiFg5mwk62eV7xMIOqtkAsc7bMpkeDSSGvF00usph0=";
      "aarch64-linux" = "sha256-F/JMrh0+0FwaKfBUKK5sWP/zuq2+89eFnOYGMQSoo/U=";
      "x86_64-linux" = "sha256-EvlPFFNN2gYq6lXdqwV3N2kBxNE2tMqJto2SIT9JwNo=";
    };
    platformMap = {
      "aarch64-darwin" = "macos-arm64";
      "aarch64-linux" = "linux-arm64-musl";
      "x86_64-linux" = "linux-x64-musl";
    };
    url = platform: "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-${platform}";
    extraAttrs = prev: {
      nativeBuildInputs = [prev.installShellFiles prev.makeWrapper prev.usage];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/libexec/mise $out/share/man/man1
        cp $src $out/libexec/mise/mise
        chmod +x $out/libexec/mise/mise
        makeWrapper $out/libexec/mise/mise $out/bin/mise \
          --prefix PATH : ${prev.lib.makeBinPath [prev.usage]}

        $out/bin/mise completion bash > mise.bash
        $out/bin/mise completion fish > mise.fish
        $out/bin/mise completion zsh > _mise
        substituteInPlace mise.bash mise.fish _mise \
          --replace 'type -p usage' 'test -x ${prev.lib.getExe prev.usage}' \
          --replace 'command usage ' 'command ${prev.lib.getExe prev.usage} '
        installShellCompletion --cmd mise \
          --bash mise.bash \
          --fish mise.fish \
          --zsh _mise

        $out/bin/mise usage > mise.usage.kdl
        usage generate manpage --file mise.usage.kdl --out-file $out/share/man/man1/mise.1
        gzip -9 $out/share/man/man1/mise.1
        runHook postInstall
      '';
    };
    meta = {
      description = "Dev tools, env vars, task runner";
      homepage = "https://github.com/jdx/mise";
    };
  };

  # Pkl - configuration as code language
  # nixpkgs の更新から独立して、セキュリティ修正を含む最新 patch release を使用する。
  # Renovate: datasource=github-releases depName=apple/pkl
  pkl = mkBinaryRelease rec {
    pname = "pkl";
    version = "0.32.1";
    hashes = {
      "aarch64-darwin" = "sha256-Vj61HJogsWo2JUZO10XGde2XUDgfISZyJpag18rB2dM=";
      "aarch64-linux" = "sha256-p20t1H2kNaj5EbA0c3P0fH5Z6lT7df+EbSC43xDboFg=";
      "x86_64-linux" = "sha256-MYC2LalcDK0dkE6btsX0qPkDJBPCHlMZS7kf8e5fMhE=";
    };
    platformMap = {
      "aarch64-darwin" = "macos-aarch64";
      "aarch64-linux" = "linux-aarch64";
      "x86_64-linux" = "linux-amd64";
    };
    url = platform: "https://github.com/apple/pkl/releases/download/${version}/pkl-${platform}";
    meta = {
      description = "Configuration-as-code language with rich validation and tooling";
      homepage = "https://pkl-lang.org";
      license = "asl20";
    };
  };

  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.268";
    # hash は Google の manifest.json (publisher 公開 checksum) から取得するため
    # 汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "manifest";
    hashes = {
      "aarch64-darwin" = "sha256-BqltVCP4N3DxIIWfHFjmDXJSzEwSKqEwQ7fnzXFrx2o=";
      "aarch64-linux" = "sha256-EW/QMfk57x4J7fFw1ixInhzCjta/vaSflIdzuhaMj2I=";
      "x86_64-linux" = "sha256-lpGit715ZxLKjP+44y5U/3/EW2YlQCMxcaFqlKBCVlM=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    url = platform: "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";
    binName = "claude";
    meta = {
      description = "Claude Code - an agentic coding tool";
      homepage = "https://github.com/anthropics/claude-code";
      license = "unfree";
    };
  };

  # Codex - OpenAI Codex CLI
  # Renovate: datasource=github-releases depName=openai/codex
  codex = mkBinaryRelease rec {
    pname = "codex";
    version = "0.154.0";
    # hash は release の codex-package_SHA256SUMS (publisher 公開 checksum) から取得する
    # ため汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "sha256sums";
    hashes = {
      "aarch64-darwin" = "sha256-QnynTAJwSeDNGjMNYR5/jR/g8etqbYWsFvYbzyy0pIU=";
      "aarch64-linux" = "sha256-l9k+Ed9y08JnctsBnm6ou3LCRlANRrmMdgg58yQDVeY=";
      "x86_64-linux" = "sha256-/G4+O4Xyz31mRSDuXGan/kqhK659RoNPR+LxZf0Nb3g=";
    };
    platformMap = {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-musl";
      "x86_64-linux" = "x86_64-unknown-linux-musl";
    };
    url = platform: "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform}.tar.gz";
    format = "tar";
    # installPhase を丸ごと差し替えるため binPath は使わない
    extraAttrs = {
      sourceRoot = ".";
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R bin codex-package.json codex-path "$out/"
        if [ -d codex-resources ]; then
          cp -R codex-resources "$out/"
        fi
        runHook postInstall
      '';
    };
    meta = {
      description = "OpenAI Codex CLI";
      homepage = "https://github.com/openai/codex";
      license = "asl20";
    };
  };

  # kakehashi - Tree-sitter Language Server
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=atusy/kakehashi
  kakehashi = mkBinaryRelease rec {
    pname = "kakehashi";
    version = "1.0.0";
    hashes = {
      "aarch64-darwin" = "sha256-RCHuPqtaIrO2f/6bQqMD5TNZuZUf3zGfjJWHw2uvSxc=";
      "aarch64-linux" = "sha256-xoUOspVDg4A4b3EcqFHtmnRzEOPmdz08YLNceU6brzQ=";
      "x86_64-linux" = "sha256-R9QLFm85h0QqnGJP+j1QU3t7e5SiOmfNZjhX8y2mPtA=";
    };
    platformMap = appleGnuPlatformMap;
    url = platform: "https://github.com/atusy/kakehashi/releases/download/v${version}/kakehashi-v${version}-${platform}.tar.gz";
    format = "tar";
    extraAttrs = {sourceRoot = ".";};
    meta = {
      description = "Tree-sitter Language Server for embedded languages";
      homepage = "https://github.com/atusy/kakehashi";
    };
  };

  # DCD - D Completion Daemon (serve-d の補完バックエンド)
  # dcd-server / dcd-client の2バイナリを同梱。serve-d は dcd-server と直接通信するため
  # どちらも $out/bin に配置する必要がある。
  # Renovate: datasource=github-releases depName=dlang-community/DCD
  dcd = mkBinaryRelease rec {
    pname = "dcd";
    version = "0.17.8";
    hashes = {
      "aarch64-darwin" = "sha256-q+EQtXnehXgVKhtmKrPtMDfnNn5JoCWbgo+LTM1KoPk=";
      "aarch64-linux" = "sha256-KqKYocMSlhGDEsHvOhmdRugNNvftp8nngzkPoI1ml6E=";
      "x86_64-linux" = "sha256-fGyzS7jdCTs1OsyGbyrGRCQ2mkhiFJPCVdnwA/Yg8hY=";
    };
    platformMap = {
      "aarch64-darwin" = "osx-aarch64";
      "aarch64-linux" = "linux-aarch64";
      "x86_64-linux" = "linux-x86_64";
    };
    url = platform: "https://github.com/dlang-community/DCD/releases/download/v${version}/dcd-v${version}-${platform}.tar.gz";
    format = "tar";
    # mkBinaryRelease は単一バイナリ前提なので installPhase を上書きして 2 バイナリ配置する
    extraAttrs = {
      sourceRoot = ".";
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp dcd-server dcd-client $out/bin/
        chmod +x $out/bin/dcd-server $out/bin/dcd-client
        runHook postInstall
      '';
    };
    meta = {
      description = "D Completion Daemon - autocompletion for the D programming language";
      homepage = "https://github.com/dlang-community/DCD";
      mainProgram = "dcd-server";
    };
  };

  # octorus - TUI tool for GitHub PR review
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=ushironoko/octorus
  octorus = mkBinaryRelease rec {
    pname = "octorus";
    version = "0.7.2";
    hashes = {
      "aarch64-darwin" = "sha256-Uv5MKlwgZqG1XaS75yZ5QkVJ8nqlwjWndN9LAv5ZIAI=";
      "aarch64-linux" = "sha256-Rk1Qk1PE1IcEixBaLCbzpUPzkfP5NAFAhiVYr7ZRGnc=";
      "x86_64-linux" = "sha256-Y+LsJQcs0zd/6J8UxDgO7Zy8df6+FBLSu5R3+9jcnDM=";
    };
    platformMap = appleGnuPlatformMap;
    url = platform: "https://github.com/ushironoko/octorus/releases/download/v${version}/octorus-${version}-${platform}.tar.gz";
    format = "tar";
    binName = "or";
    meta = {
      description = "TUI tool for GitHub PR review with Vim-style keybindings";
      homepage = "https://github.com/ushironoko/octorus";
    };
  };

  # k1LoW/deck - Markdown to Google Slides
  # darwin は zip、linux は tar.gz と配布形式が異なるため format をプラットフォーム別に指定する。
  # アーカイブ内のバイナリ名は deck だが deck-slides として公開する (binPath/binName で改名)。
  # Renovate: datasource=github-releases depName=k1LoW/deck
  deck-slides = mkBinaryRelease rec {
    pname = "deck-slides";
    version = "1.24.1";
    hashes = {
      "aarch64-darwin" = "sha256-0+CgaPZe1LUYQ41aAZivRXrX/G4N8A4tIBIRoZviAa4=";
      "aarch64-linux" = "sha256-o++kGQaOtuHknDzzGMxgNb/fjzkwXgnUPIpfzaMzWSg=";
      "x86_64-linux" = "sha256-1+ORW0ZHy8qZSULt92mecgctotUaIZSUzakNYfOJaVY=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin_arm64.zip";
      "aarch64-linux" = "linux_arm64.tar.gz";
      "x86_64-linux" = "linux_amd64.tar.gz";
    };
    format = {
      "aarch64-darwin" = "zip";
      "aarch64-linux" = "tar";
      "x86_64-linux" = "tar";
    };
    url = platform: "https://github.com/k1LoW/deck/releases/download/v${version}/deck_v${version}_${platform}";
    binPath = "deck";
    extraAttrs = {sourceRoot = ".";};
    meta = {
      description = "A tool for creating deck using Markdown and Google Slides";
      homepage = "https://github.com/k1LoW/deck";
      license = "mit";
      mainProgram = "deck-slides";
    };
  };
}
