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
    version = "2026.6.14";
    hashes = {
      "aarch64-darwin" = "sha256-L3Ck338S1QImw0uFeCHID5EbOCWYzz95cunQ3uBwa7k=";
      "aarch64-linux" = "sha256-SGJllxDYdQ2EXhUoQhNKRH6K66plfCe00JpYn/rtJzY=";
      "x86_64-linux" = "sha256-+e9V3gqLwuEpCDfZ1QI0e4Cuw4fI1fMsOd1SiMl7o2Y=";
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
    version = "2.5.1";
    hashes = {
      "aarch64-darwin" = "sha256-CP0HtTUD/EM1hu7LTuuSSR26CzHeoKp9wVipNXNKHEw=";
      "aarch64-linux" = "sha256-1rw88eSOXsYxIo9Gq3g8uFZM7zB44STHL3MomBZj+Xk=";
      "x86_64-linux" = "sha256-vrRC5cm+p/Uq5tbrauSBk4iotZBJLWcGud//yoCI8GY=";
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
    version = "2.1.207";
    # hash は Google の manifest.json (publisher 公開 checksum) から取得するため
    # 汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "manifest";
    hashes = {
      "aarch64-darwin" = "sha256-E5egYsaIlnUFXjMU3ZVjdqxRJip3NK2egZwml11xVHo=";
      "x86_64-darwin" = "sha256-ikNV0lGmDJDYzwjzL9siqBV909CFVC+V0NoEdfmixXw=";
      "aarch64-linux" = "sha256-i8FKKEBlODRg83mB1yS496p8qTyYSdL+Nn4I8DOD9FQ=";
      "x86_64-linux" = "sha256-hefpiKOS2Fn5CALKIfsm6J08mrUn9e0LCN85VeNNXIM=";
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
    version = "0.144.4";
    # hash は release の codex-package_SHA256SUMS (publisher 公開 checksum) から取得する
    # ため汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "sha256sums";
    hashes = {
      "aarch64-darwin" = "sha256-MS5vooJllvsjzBGTww1RkCtlIsNszEOzZBdZDg69Uz0=";
      "x86_64-darwin" = "sha256-ZmZx++dh/h/VfXTnJcWjBnKfgfT778FqAaBZXmmGTUE=";
      "aarch64-linux" = "sha256-sbxWGlv3T5xXZ8aYJ1roBDzuLORTQQmASLCwuLTiz8U=";
      "x86_64-linux" = "sha256-0Ke9ssqCHJu19MwvsRpO2WAl22OyDRvd8eYyNhoQgiA=";
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
    version = "0.7.0";
    hashes = {
      "aarch64-darwin" = "sha256-0uQk+PcVEuea2xUz/Xwb0u+7O7BjcAfmCCOK08kLlY8=";
      "x86_64-darwin" = "sha256-25y2/zAGDpoxcKTbVMBMXW4x3hQHbA6JkoifnKRH/i0=";
      "aarch64-linux" = "sha256-5lgLC0cQpBVX6zbZ7fqjh6CjSevoZPA+5/uDwWmZSBE=";
      "x86_64-linux" = "sha256-PeHYDvWwVe8OeyM5ficGs/dq5PNMI99F544RsddQU24=";
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
    version = "0.6.6";
    hashes = {
      "aarch64-darwin" = "sha256-JzjEwUAieepLLrmCVU9EX5Uv6r7dehx/Io75M8RFzYA=";
      "x86_64-darwin" = "sha256-RVNSxelmOWp8V0NuAGzp4ufnVqz+plb6m2Wa5vwPIIw=";
      "aarch64-linux" = "sha256-iqitDRQs5PCqHq2VhDweCusrCCz0zT8htCWjnPcxv8U=";
      "x86_64-linux" = "sha256-G7egRF11bjnJoiQ5uP8Hrb6EKnNHHk4DQ2IYU8P/DDg=";
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
    version = "0.14.1";
    hashes = {
      "aarch64-darwin" = "sha256-gdjKojHrjsgE5Ytgjq8ZHqgRpz8yYEXSn+2+qf2vWbw=";
      "x86_64-darwin" = "sha256-XlqyJmuk8sELrQ4ti0W33gi0BnqjzVJJftFA3WRAvLM=";
      "aarch64-linux" = "sha256-9Wp9ScdUitN7YLxSs3QoBV/qzVEnHdaqPNwu4KZSF7Q=";
      "x86_64-linux" = "sha256-y21ExogHIjHxbmRd2/THd51pylcQzHTjTVkwGGjIggk=";
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
    version = "1.24.0";
    hashes = {
      "aarch64-darwin" = "sha256-fNvfaTb66xqbjd1nUHgnJWQGmtQ0hXf2ngog5jTD1CY=";
      "x86_64-darwin" = "sha256-n6fc2s9D5YR8kEfyeACJ8AdLfNT4AoWN1Fc7veNxtdU=";
      "aarch64-linux" = "sha256-Wbn0ww2GzNCB3n4t+TwZb/4kQrZv9imjlRADUtOEtGE=";
      "x86_64-linux" = "sha256-5TiGpxeG9/gryjeICKXeOL+XITdt0tuLej277AjMI6E=";
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
