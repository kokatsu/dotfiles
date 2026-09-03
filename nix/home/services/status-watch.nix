{
  pkgs,
  lib,
  isWSL,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # systemd unit と launchd agent で同じ入口を共有する。PATH を固定するのは
  # どちらのスケジューラもログインシェルの PATH を継承しないため
  checkScript = pkgs.writeShellScript "status-watch-check" ''
    export PATH="${lib.makeBinPath (with pkgs; [bash coreutils curl jq])}"
    exec "$HOME/.local/bin/scripts/status-watch" check
  '';
in
  lib.mkMerge [
    (lib.mkIf isWSL {
      systemd.user.services.status-watch = {
        Unit = {
          Description = "Check Claude, OpenAI, and GitHub status for the WezTerm status bar";
        };
        Service = {
          Type = "oneshot";
          ExecStart = toString checkScript;
        };
      };

      systemd.user.timers.status-watch = {
        Unit = {
          Description = "Check Claude, OpenAI, and GitHub status every 5 minutes";
        };
        Timer = {
          OnCalendar = "*:0/5";
          Persistent = true;
        };
        Install = {
          WantedBy = ["timers.target"];
        };
      };
    })

    (lib.mkIf isDarwin {
      launchd.agents.status-watch = {
        enable = true;
        config = {
          ProgramArguments = [(toString checkScript)];
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
