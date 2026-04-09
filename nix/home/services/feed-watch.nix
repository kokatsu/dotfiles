{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in
  lib.mkIf (!isDarwin) {
    systemd.user.services.feed-watch = {
      Unit = {
        Description = "Check GitHub feeds for new commits";
      };
      Service = {
        Type = "oneshot";
        ExecStart = toString (pkgs.writeShellScript "feed-watch-check" ''
          export PATH="${lib.makeBinPath (with pkgs; [gh jq curl coreutils gnused gnugrep claude-code])}"
          "$HOME/.local/bin/scripts/feed-watch" check
          exec "$HOME/.local/bin/scripts/feed-summarize"
        '');
      };
    };

    systemd.user.timers.feed-watch = {
      Unit = {
        Description = "Check GitHub feeds every hour";
      };
      Timer = {
        OnCalendar = "hourly";
        Persistent = true;
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };
  }
