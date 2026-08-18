let
  lib = import ./lib.nix;
  inherit (lib) mkBinaryRelease;
  appleGnuPlatformMap = {
    "aarch64-darwin" = "aarch64-apple-darwin";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "aarch64-linux" = "aarch64-unknown-linux-gnu";
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
  };
  currentAppleGnuPlatformMap = removeAttrs appleGnuPlatformMap ["x86_64-darwin"];
in {
  # mise - dev tools, env vars, task runner
  # Renovate: datasource=github-releases depName=jdx/mise
  mise = mkBinaryRelease rec {
    pname = "mise";
    version = "2026.8.2";
    hashes = {
      "aarch64-darwin" = "sha256-w2lYBl9/QobW7fcHckcwLP8dp3yBraT6mjVmwOqH4gA=";
      "aarch64-linux" = "sha256-o3U0OCdp/AHTQqzphl+R4Hhsz7VJf3pRXo2VdCYu+qw=";
      "x86_64-linux" = "sha256-gR3YjTDy6ugE5No5PLG7XnsCP6QnZprE/erFjL4IGbw=";
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

  # Biome - formatter and linter for web projects
  # Renovate: datasource=github-releases depName=biomejs/biome
  biome = mkBinaryRelease rec {
    pname = "biome";
    version = "2.5.3";
    hashes = {
      "aarch64-darwin" = "sha256-YQ0+HncNNzNo1MzuWhnF4XNbAjUCT8vtauB+sIDTuwk=";
      "aarch64-linux" = "sha256-tkLe1Drrytc4kmtA7v1Nwhh6IG0fv7N6RfHbSYaATb0=";
      "x86_64-linux" = "sha256-q450ryNmEnMG4lBlLS8yvRk2AfII/NBgQRIIDAyjJFs=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "aarch64-linux" = "linux-arm64";
      "x86_64-linux" = "linux-x64";
    };
    url = platform: "https://github.com/biomejs/biome/releases/download/%40biomejs%2Fbiome%40${version}/biome-${platform}";
    meta = {
      description = "Formatter and linter for web projects";
      homepage = "https://github.com/biomejs/biome";
      license = "mit";
    };
  };

  # Yazi - terminal file manager
  # Renovate: datasource=github-releases depName=sxyazi/yazi
  yazi = mkBinaryRelease rec {
    pname = "yazi";
    version = "26.5.6";
    hashes = {
      "aarch64-darwin" = "sha256-er1xcl4v4nvtA2vsv2znn6F5ZOtoSR00GQARyUuMfKg=";
      "aarch64-linux" = "sha256-w4sHlh5/xMdlA/0PShtL0LN5qZg1uBjNiZsDFcco4eE=";
      "x86_64-linux" = "sha256-HJCW8Kg7gQLBlDhfZEze/5PMgmlCYWPJ0DMEHr1Te9I=";
    };
    platformMap = currentAppleGnuPlatformMap;
    url = platform: "https://github.com/sxyazi/yazi/releases/download/v${version}/yazi-${platform}.zip";
    format = "zip";
    extraAttrs = prev: {
      nativeBuildInputs = [prev.makeWrapper];
      sourceRoot = ".";
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/libexec/yazi-bin
        find . -type f -name yazi -exec cp {} $out/libexec/yazi-bin/yazi \; -quit
        find . -type f -name ya -exec cp {} $out/libexec/yazi-bin/ya \; -quit
        chmod +x $out/libexec/yazi-bin/yazi $out/libexec/yazi-bin/ya
        makeWrapper $out/libexec/yazi-bin/yazi $out/bin/yazi \
          --prefix PATH : ${
          prev.lib.makeBinPath [
            prev._7zz
            prev.chafa
            prev.fd
            prev.ffmpeg-headless
            prev.file
            prev.fzf
            prev.imagemagick
            prev.jq
            prev.poppler-utils
            prev.resvg
            prev.ripgrep
            prev.zoxide
          ]
        }
        ln -s $out/libexec/yazi-bin/ya $out/bin/ya
        runHook postInstall
      '';
    };
    meta = {
      description = "Blazing fast terminal file manager";
      homepage = "https://github.com/sxyazi/yazi";
    };
  };

  # Difftastic - structural diff tool
  # Renovate: datasource=github-releases depName=Wilfred/difftastic
  difftastic = mkBinaryRelease rec {
    pname = "difftastic";
    version = "0.69.0";
    hashes = {
      "aarch64-darwin" = "sha256-yVi4eIWlglo1bFiZrH7N11KnlCCEGZ8r5LwL+MnejjM=";
      "aarch64-linux" = "sha256-q9L0LSr9QkMStIYqp8e7AyBEdnCuIvq8xRWdsD4tzL0=";
      "x86_64-linux" = "sha256-A425ag6PzmnyVU4z4E/3X79vlupFy07bntYgOixHUP8=";
    };
    platformMap = currentAppleGnuPlatformMap;
    url = platform: "https://github.com/Wilfred/difftastic/releases/download/${version}/difft-${platform}.tar.gz";
    format = "tar";
    binName = "difft";
    extraAttrs = {
      sourceRoot = ".";
    };
    meta = {
      description = "Structural diff tool that understands syntax";
      homepage = "https://github.com/Wilfred/difftastic";
    };
  };

  # Claude Code - agentic coding tool
  # Renovate: datasource=custom.claude-code depName=claude-code
  claude-code = mkBinaryRelease rec {
    pname = "claude-code";
    version = "2.1.234";
    # hash は Google の manifest.json (publisher 公開 checksum) から取得するため
    # 汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "manifest";
    hashes = {
      "aarch64-darwin" = "sha256-CNhwAxNpfL5zCiVCDJCKKZzlLVbw6yz0+slMq1EJvFc=";
      "x86_64-darwin" = "sha256-GnsuiUhgnx9zKmSYzRe4BbXFGH10qZrcYeuqWinvw0w=";
      "aarch64-linux" = "sha256-JK3aZzWRzYNFsD7IJFkVuxUaJZoevD7yNkm1e6lEqqI=";
      "x86_64-linux" = "sha256-NHNgHqaV1b92nFsgKETUy0+/cjrplUUPy2lzIEd1yEo=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "x86_64-darwin" = "darwin-x64";
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
    version = "0.147.0";
    # hash は release の codex-package_SHA256SUMS (publisher 公開 checksum) から取得する
    # ため汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "sha256sums";
    hashes = {
      "aarch64-darwin" = "sha256-F7KYTrIrYH49DCVyglL8kPUQ5Ha605ptn0XNsapoVDI=";
      "x86_64-darwin" = "sha256-2R5ZEz2vkjvEXXbj2kr4rp72KgIx2hhIjaDNVztunWM=";
      "aarch64-linux" = "sha256-icv3m9Wub5xY2kfoB58xHIQhk1DJxDwHDULz6bKoFAE=";
      "x86_64-linux" = "sha256-vXWNU9VuQdxl4EX0WJ33mgOO0ZegEa3LUqJY5q1kz9o=";
    };
    platformMap = {
      "aarch64-darwin" = "aarch64-apple-darwin";
      "x86_64-darwin" = "x86_64-apple-darwin";
      "aarch64-linux" = "aarch64-unknown-linux-musl";
      "x86_64-linux" = "x86_64-unknown-linux-musl";
    };
    url = platform: "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform}.tar.gz";
    format = "tar";
    binPath = "bin/codex";
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
    version = "0.9.0";
    hashes = {
      "aarch64-darwin" = "sha256-m6NKN1O+0cVpU4H89c0ep/acd7blWXGpDjw8K6HUTRY=";
      "x86_64-darwin" = "sha256-NlBcjw/5cF2YYfjqRfj3qm6U8jZpOgbr2eND53W9PLA=";
      "aarch64-linux" = "sha256-oi4ENFAN8ak2GiQAww0yitzlqoieEaj46OfYPMT8PAs=";
      "x86_64-linux" = "sha256-Nx75WQ42Xzqb3ehSIIIW0rB/2mT5kfNdI5CdT8rKZ5Q=";
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
    version = "0.16.2";
    hashes = {
      "aarch64-darwin" = "sha256-WvO183eZWB5oRZbRpny3wdzMe+WhJD6eA4f7FoHbFxU=";
      "x86_64-darwin" = "sha256-FUtV75znNLsdObbqSS9rixxy8flRRXNQTUMN7f6m77k=";
      "aarch64-linux" = "sha256-ZTXSUNDNo4g7zqWUacu5NvzPMdq9ijuaM9/hldRhTKo=";
      "x86_64-linux" = "sha256-QGrA29Hadd2asAgLaF0XD0xY/l3FeAfQMctBDu3aj+I=";
    };
    platformMap = {
      "aarch64-darwin" = "osx-aarch64";
      "x86_64-darwin" = "osx-x86_64";
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
      "x86_64-darwin" = "sha256-nhpkySav6FiZczOEFdU5z+XWVZA+qxquzRqlycXymi0=";
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

  # rgx - Terminal regex tester (regex101 for the terminal)
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=brevity1swos/rgx
  rgx-cli = mkBinaryRelease rec {
    pname = "rgx-cli";
    version = "0.14.2";
    hashes = {
      "aarch64-darwin" = "sha256-UiIj6w2Q6CQrOJG2VJfhdz3da6KLnuak+pTfG/QnHgM=";
      "x86_64-darwin" = "sha256-1U5+OABp3b+fRd1/D2iLVsaQyMnelnzpcljNtzexfek=";
      "aarch64-linux" = "sha256-5Wwsave4c+Ybw6ZSkt4B83SOfkIUxxMtjZVtEdffHF4=";
      "x86_64-linux" = "sha256-pbOiSykZBZFVS8R9Fb/711X/WV9s5l17F4+dv3lHSzc=";
    };
    platformMap = appleGnuPlatformMap;
    url = platform: "https://github.com/brevity1swos/rgx/releases/download/v${version}/rgx-cli-${platform}.tar.xz";
    format = "tar";
    binName = "rgx";
    meta = {
      description = "Terminal regex tester with real-time matching and multi-engine support";
      homepage = "https://github.com/brevity1swos/rgx";
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
      "x86_64-darwin" = "sha256-f3HaLmrdzY2/FcwMYa0HHKpgj+rkGW0H9/Alg4G+UYI=";
      "aarch64-linux" = "sha256-o++kGQaOtuHknDzzGMxgNb/fjzkwXgnUPIpfzaMzWSg=";
      "x86_64-linux" = "sha256-1+ORW0ZHy8qZSULt92mecgctotUaIZSUzakNYfOJaVY=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin_arm64.zip";
      "x86_64-darwin" = "darwin_amd64.zip";
      "aarch64-linux" = "linux_arm64.tar.gz";
      "x86_64-linux" = "linux_amd64.tar.gz";
    };
    format = {
      "aarch64-darwin" = "zip";
      "x86_64-darwin" = "zip";
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
