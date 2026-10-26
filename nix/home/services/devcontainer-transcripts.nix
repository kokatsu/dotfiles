{
  config,
  pkgs,
  lib,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  configDir = config.home.sessionVariables.CLAUDE_CONFIG_DIR;

  # devcontainer の Claude の設定 volume にある jsonl と、jsonl に残らないコストを持つ
  # cc-statusline の statusline-unlogged/*.bin を、ホストの cc-statusline が読む場所へ写す。
  # `*-claude` は compose で付けた名前、`claude-code-config-*` は Anthropic の devcontainer の
  # 例に倣った名前。jsonl の写し先に `devcontainer-` を付けるのは、ホストと同じパスにマウントした
  # コンテナのセッションがホストの /resume の一覧に混ざらないため。
  # docker CLI を Nix から渡すのは、WSL の docker が apt 由来でスケジューラの PATH に無いため
  sync = pkgs.writeShellScript "devcontainer-transcripts-sync" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [pkgs.docker-client pkgs.coreutils]}"
    owner="$(id -u):$(id -g)"
    unlogged="${configDir}/statusline-unlogged"
    docker volume ls --quiet | while IFS= read -r volume; do
      case $volume in
        *-claude | claude-code-config-*) ;;
        *) continue ;;
      esac
      projects="${configDir}/projects/devcontainer-$volume"
      # 先に作らないと docker が root の所有で作る
      mkdir -p "$projects" "$unlogged"
      # volume の projects はコンテナのユーザーだけが読める (700) ので root で読み、
      # 写したものをホストのユーザーの所有に変える
      docker run --rm --network none --env OWNER="$owner" \
        --volume "$volume:/src:ro" --volume "$projects:/projects" --volume "$unlogged:/unlogged" \
        alpine:3.20 sh -euc '
          copy() {
            src=$1 dst=$2
            shift 2
            [ -d "$src" ] || return 0
            cd "$src"
            find . -type f "$@" | while IFS= read -r f; do
              d="$dst/$f"
              if [ ! -e "$d" ] || [ "$f" -nt "$d" ]; then
                mkdir -p "$(dirname "$d")"
                # cc-statusline は *.jsonl を読み、statusline-unlogged の古い *.tmp を消すので、
                # どちらでもない名前で書いてから置き換える
                cp "$f" "$d.part"
                chown "$OWNER" "$d.part"
                touch -r "$f" "$d.part"
                mv "$d.part" "$d"
              fi
            done
            find "$dst" -type d ! -user "''${OWNER%:*}" -exec chown "$OWNER" {} +
          }
          copy /src/projects /projects -name "*.jsonl"
          # cc-statusline は 25 時間更新のない *.bin を消す。それより古いものを写すと、消すたびに写し直す
          copy /src/statusline-unlogged /unlogged -name "*.bin" -mmin -1500
        '
    done
  '';
in
  lib.mkMerge [
    (lib.mkIf isWSL {
      systemd.user.services.devcontainer-transcripts = {
        Unit.Description = "Copy devcontainer Claude transcripts for cc-statusline";
        Service = {
          Type = "oneshot";
          ExecStart = toString sync;
        };
      };

      systemd.user.timers.devcontainer-transcripts = {
        Unit.Description = "Copy devcontainer Claude transcripts every minute";
        Timer.OnCalendar = "minutely";
        Install.WantedBy = ["timers.target"];
      };
    })

    (lib.mkIf isDarwin {
      launchd.agents.devcontainer-transcripts = {
        enable = true;
        config = {
          ProgramArguments = [(toString sync)];
          # スリープ中の発火は落ちるが、次の実行で差分をまとめて写す
          StartInterval = 60;
          RunAtLoad = true;
          ProcessType = "Background";
        };
      };
    })
  ]
