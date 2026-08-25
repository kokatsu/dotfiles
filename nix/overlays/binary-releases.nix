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
    version = "2.5.9";
    hashes = {
      "aarch64-darwin" = "sha256-fYtR3shX/6iqNc5eqjpEds1ivtATrcKJa/Q8rApnp5s=";
      "aarch64-linux" = "sha256-v1k/eVXjpDf7gFayVRQrUIcrqj6BNxzaLD/OkjmvGJA=";
      "x86_64-linux" = "sha256-AT61FYueUyNdu/MSVcs7d2+5M4sy+m/0pE7hzu1l7mM=";
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
    version = "26.8.15";
    hashes = {
      "aarch64-darwin" = "sha256-P1SQfqCKvpZQb0siI5NA7Ykjpq6urnjzPVm85X2spM0=";
      "aarch64-linux" = "sha256-9ahXcfBrsOjEiBNq4K7a7I00GnzumVVJ3zkdfYUv6NE=";
      "x86_64-linux" = "sha256-zGfreZFVDC+UB82lLT9a8JN2J6pohOfemaBPzwWYB+A=";
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
    version = "0.70.0";
    hashes = {
      "aarch64-darwin" = "sha256-GSEmciH8tXedMMTcwLO0Ygq76FH/1VlqRxVXZYFRj1E=";
      "aarch64-linux" = "sha256-5yloSQfWfRoXJ6CPRDh34Z5A7rLv682Vwbj3/uQoTo4=";
      "x86_64-linux" = "sha256-KZfSu+YgU07b15sASfAM6E7vP+2xXHgiRW1Y442LBck=";
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
    version = "2.1.245";
    # hash は Google の manifest.json (publisher 公開 checksum) から取得するため
    # 汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "manifest";
    hashes = {
      "aarch64-darwin" = "sha256-n3wiYCUXZaGNCzUZhmnazBkS9ugSmjsB9rWNkzZf8fE=";
      "x86_64-darwin" = "sha256-3gRLtUPoJjUvMVh6dDVuGy2ulNwbnJYKNi2fB9+Wwqc=";
      "aarch64-linux" = "sha256-0NopkwPXEKfMXN7OlimVj1EozhpyfhVGPGUe1c84XH8=";
      "x86_64-linux" = "sha256-Fq0rlN6veymr7ZZtmByZkaR68EIPW+jtSj+Dvqn2eLw=";
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
    version = "0.149.1";
    # hash は release の codex-package_SHA256SUMS (publisher 公開 checksum) から取得する
    # ため汎用 prefetch ループの対象外。更新は pr.yml の個別ステップが担う。
    hashSource = "sha256sums";
    hashes = {
      "aarch64-darwin" = "sha256-TLsXRotdhrSxgqKMAW1i6dJzokHOwEiFzPrnbmmDrj8=";
      "x86_64-darwin" = "sha256-TFD7krsjikBnAJ1KmcEzUTJciEDake3Qzk5beiHVO8M=";
      "aarch64-linux" = "sha256-Vwlfn0ztNtjhc/Z+JsXBQtWz4eGYS7yuNWhCCe0japs=";
      "x86_64-linux" = "sha256-HoUxrl9t6jxuEeU+dMxayBvxull/mylvsRLW6jD9r10=";
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

  # agent-browser - AI エージェント向けブラウザ自動化 CLI
  # nixpkgs は 0.27.0 で停滞しているため overlay で上書きする。v0.30.0 で入った
  # read (Chrome を起動せず markdown を取得する) を browser-research スキルと
  # feed-summarize が使う。Linux は静的リンクの musl ビルドを選ぶ (mise と同じ方針)。
  # Renovate: datasource=github-releases depName=vercel-labs/agent-browser
  agent-browser = mkBinaryRelease rec {
    pname = "agent-browser";
    version = "0.34.0";
    hashes = {
      "aarch64-darwin" = "sha256-1oCnqWq4bpq50rVxsSkZt2HpNoKtHecUu9WshJyNfJw=";
      "aarch64-linux" = "sha256-wIZPsgbjIa9IpG+4MxzwiuYLP8wQRiMsHRyELbT8QMo=";
      "x86_64-linux" = "sha256-3UdSuh3vgcdENQTChLZVnSja2OzQK1+uymyvT8H7lI4=";
    };
    platformMap = {
      "aarch64-darwin" = "darwin-arm64";
      "aarch64-linux" = "linux-musl-arm64";
      "x86_64-linux" = "linux-musl-x64";
    };
    url = platform: "https://github.com/vercel-labs/agent-browser/releases/download/v${version}/agent-browser-${platform}";
    meta = {
      description = "Browser automation CLI for AI agents";
      homepage = "https://github.com/vercel-labs/agent-browser";
      license = "asl20";
    };
  };

  # kakehashi - Tree-sitter Language Server
  # Uses pre-built binaries from GitHub releases
  # Renovate: datasource=github-releases depName=atusy/kakehashi
  kakehashi = mkBinaryRelease rec {
    pname = "kakehashi";
    version = "0.10.0";
    hashes = {
      "aarch64-darwin" = "sha256-h74rgZ5xlZTavTdRezGz44cFzE01Z2GDE8XWiULMHI8=";
      "x86_64-darwin" = "sha256-C3wwu+Camz+keMP9YtRTs/gNxiXe4UVTk2ANABztxGE=";
      "aarch64-linux" = "sha256-3CcRS49Uqw6c/UoB/0225U3Kk3emMIt8pEfeOaaifxw=";
      "x86_64-linux" = "sha256-2bwagj33LKEi/zufSXeOxbTFn8hUtGm2fV2FC7W942Q=";
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
    version = "0.16.3";
    hashes = {
      "aarch64-darwin" = "sha256-q+EQtXnehXgVKhtmKrPtMDfnNn5JoCWbgo+LTM1KoPk=";
      "x86_64-darwin" = "sha256-ALLzZ332AifhEPBhtYkNUBswSogn5fMZ8PbufmuZAeY=";
      "aarch64-linux" = "sha256-KqKYocMSlhGDEsHvOhmdRugNNvftp8nngzkPoI1ml6E=";
      "x86_64-linux" = "sha256-fGyzS7jdCTs1OsyGbyrGRCQ2mkhiFJPCVdnwA/Yg8hY=";
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
