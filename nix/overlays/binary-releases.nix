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
  # Pkl - configuration as code language
  # nixpkgs の更新から独立して、セキュリティ修正を含む最新 patch release を使用する。
  # Renovate: datasource=github-releases depName=apple/pkl
  pkl = mkBinaryRelease rec {
    pname = "pkl";
    version = "0.32.2";
    hashes = {
      "aarch64-darwin" = "sha256-RmlS8LMMk9+jY5Ols2lRWZF85CkePJNqGKCiQM++mOk=";
      "aarch64-linux" = "sha256-5gdE4X1N3AJXo1JgmYtfmDh7XWpehoMXzM++vo2WKuM=";
      "x86_64-linux" = "sha256-h0x1SEx5rdd/sjRupKsuiHXuo1+3B4lL9UV6LfXQPe8=";
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
    version = "2.1.314";
    # hash は Google の manifest.json (publisher 公開 checksum) から取得するため
    # artifact 自体の prefetch を省き、scripts/update-hashes.ts が変換する。
    hashSource = "manifest";
    hashes = {
      "aarch64-darwin" = "sha256-a17GkRleVRsCxB3599cj9Oph6qA8LfkKzv43NvGutiA=";
      "aarch64-linux" = "sha256-3EryiRdFXgCdJnBLgqQ4NToGFJ6CW2zfeCkIstKGYfU=";
      "x86_64-linux" = "sha256-T0F4zkHYPiM0Hr+67NvPjqa/e66gaQAlq+Se7sOl0B0=";
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
    version = "0.166.0";
    # hash は release の codex-package_SHA256SUMS (publisher 公開 checksum) から取得する
    # ため artifact 自体の prefetch を省き、scripts/update-hashes.ts が変換する。
    hashSource = "sha256sums";
    hashes = {
      "aarch64-darwin" = "sha256-VaRAy1eflwq+fHmrGB5UsOpMQZvpnzM7vYaO66ycIfA=";
      "aarch64-linux" = "sha256-eCG3fdouYoP7H2PzFlF3onHaiDPoV89nPGyhyds7/MY=";
      "x86_64-linux" = "sha256-HUSyi8SsmTfX01MiZLqmilB842SVag1Ou4VvMxze4lQ=";
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
    extraAttrs = prev: {
      sourceRoot = ".";
      nativeBuildInputs = prev.lib.optionals prev.stdenv.hostPlatform.isLinux [prev.autoPatchelfHook];
      buildInputs = prev.lib.optionals prev.stdenv.hostPlatform.isLinux [prev.stdenv.cc.cc.lib];
    };
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
    version = "0.19.4";
    hashes = {
      "aarch64-darwin" = "sha256-/uG6KhdxG/LQ8ai+SDLKpMAwjeEgcBF4HnajOBg3JuM=";
      "aarch64-linux" = "sha256-ulowzpiOzl0/0ScinHpLufEUmmD1JHFxDcQeZjo7MzU=";
      "x86_64-linux" = "sha256-b/PfhRF3YpSFBqQQxA6kiB1AbJvu+aNtmwbqYkeKcKg=";
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

  # k1LoW/deck - Markdown to Google Slides
  # darwin は zip、linux は tar.gz と配布形式が異なるため format をプラットフォーム別に指定する。
  # アーカイブ内のバイナリ名は deck だが deck-slides として公開する (binPath/binName で改名)。
  # Renovate: datasource=github-releases depName=k1LoW/deck
  deck-slides = mkBinaryRelease rec {
    pname = "deck-slides";
    version = "1.24.4";
    hashes = {
      "aarch64-darwin" = "sha256-0l5uz8IBEvWReXvSqYQNYyCsG/1lM0voOj9R9kT2wE0=";
      "aarch64-linux" = "sha256-VyESNSwG07eD94mEDuWhV6Cuucpp003X4iR6qgMCZ78=";
      "x86_64-linux" = "sha256-lN/ObCXkYTJY/0i6QXhB3wYRuy8xgd/PI3gJObyCCek=";
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

  # upmd - Run tasks and workflows from Markdown
  # Renovate: datasource=github-releases depName=rezigned/upmd
  upmd = mkBinaryRelease rec {
    pname = "upmd";
    version = "0.2.7";
    hashes = {
      "aarch64-darwin" = "sha256-HpIBnGEUQudaLAHw06QNBpn8gDb4i+b8s1M+AIH8irc=";
      "aarch64-linux" = "sha256-ITx3pgLTNihQj96pzEuy5iOAMOV1KLdIylE39wVC56A=";
      "x86_64-linux" = "sha256-EBM216j0ZIo7+JTVY2h18d89IZcZ1HAJbFYuDPTWuao=";
    };
    platformMap = appleGnuPlatformMap;
    url = platform: "https://github.com/rezigned/upmd/releases/download/v${version}/upmd-${platform}.tar.xz";
    format = "tar";
    meta = {
      description = "Run tasks and workflows from Markdown";
      homepage = "https://github.com/rezigned/upmd";
    };
  };

  # # qo - Interactive TUI to query JSON and CSV with SQL
  # # Renovate: datasource=github-releases depName=kiki-ki/go-qo
  # qo = mkBinaryRelease rec {
  #   pname = "qo";
  #   version = "0.5.1";
  #   hashes = {
  #     "aarch64-darwin" = "sha256-CHNhJcxvY6bWesgZkt6Sxbga8Aru8Tu6DIaX3V3puMU=";
  #     "aarch64-linux" = "sha256-ZqUB26ngjWEGDkh9hfq4++3XGxTdGNBgFIOWDhP5UoY=";
  #     "x86_64-linux" = "sha256-ned1TYemI0C80sol93IgWBmwpDh7pk/Vr3zqAPmNjG4=";
  #   };
  #   platformMap = {
  #     "aarch64-darwin" = "darwin_arm64";
  #     "aarch64-linux" = "linux_arm64";
  #     "x86_64-linux" = "linux_amd64";
  #   };
  #   url = platform: "https://github.com/kiki-ki/go-qo/releases/download/v${version}/qo_${version}_${platform}.tar.gz";
  #   format = "tar";
  #   extraAttrs = {sourceRoot = ".";};
  #   meta = {
  #     description = "Interactive TUI to query JSON and CSV using SQL";
  #     homepage = "https://github.com/kiki-ki/go-qo";
  #   };
  # };
}
