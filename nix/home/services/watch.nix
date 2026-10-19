{
  pkgs,
  lib,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # 5 分ごとに `~/.local/bin/scripts/<name> check` を実行する監視スクリプト。
  # bash は各スクリプトの shebang (#!/usr/bin/env bash) 解決に必要
  watches = {
    disk-watch = {
      subject = "Check disk usage";
      purpose = "for the WezTerm status bar";
      deps = with pkgs; [bash coreutils gawk jq];
    };
    feed-watch = {
      subject = "Check GitHub feeds";
      purpose = "for new commits";
      deps = with pkgs; [bash deno gh jq curl yq-go coreutils gnused gnugrep util-linux];
      service.TimeoutStartSec = "10min";
    };
    status-watch = {
      subject = "Check Claude, OpenAI, and GitHub status";
      purpose = "for the WezTerm status bar";
      deps = with pkgs; [bash coreutils curl jq];
    };
  };

  # systemd unit と launchd agent で同じ入口を共有する。PATH を固定するのは
  # どちらのスケジューラもログインシェルの PATH を継承しないため
  checkScript = name: w:
    pkgs.writeShellScript "${name}-check" ''
      export PATH="${lib.makeBinPath w.deps}"
      exec "$HOME/.local/bin/scripts/${name}" check
    '';
in
  lib.mkMerge [
    (lib.mkIf isWSL {
      systemd.user.services =
        lib.mapAttrs (name: w: {
          Unit.Description = "${w.subject} ${w.purpose}";
          Service =
            {
              Type = "oneshot";
              ExecStart = toString (checkScript name w);
            }
            // w.service or {};
        })
        watches;

      systemd.user.timers =
        lib.mapAttrs (_: w: {
          Unit.Description = "${w.subject} every 5 minutes";
          Timer = {
            OnCalendar = "*:0/5";
            Persistent = true;
          };
          Install.WantedBy = ["timers.target"];
        })
        watches;
    })

    (lib.mkIf isDarwin {
      launchd.agents.status-watch = {
        enable = true;
        config = {
          ProgramArguments = [(toString (checkScript "status-watch" watches.status-watch))];
          # StartInterval はスリープ中の発火をそのまま落とす (launchd.plist(5))。
          # StartCalendarInterval なら取りこぼした分が起床時に 1 回へ集約されるので、
          # WSL 側の OnCalendar = *:0/5 + Persistent = true に挙動が近い
          StartCalendarInterval = map (minute: {Minute = minute;}) [0 5 10 15 20 25 30 35 40 45 50 55];
          RunAtLoad = true;
          ProcessType = "Background";
        };
      };
    })
  ]
