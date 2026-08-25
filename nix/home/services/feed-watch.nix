{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
  lib.mkIf (!isDarwin) {
    systemd.user.services.feed-watch = {
      Unit = {
        Description = "Check GitHub feeds for new commits";
      };
      Service = {
        Type = "oneshot";
        ExecStart = toString (pkgs.writeShellScript "feed-watch-check" ''
          # bash は feed-watch の shebang (#!/usr/bin/env bash) 解決に必要
          export PATH="${lib.makeBinPath (with pkgs; [bash gh jq curl coreutils gnused gnugrep gawk])}"
          exec "$HOME/.local/bin/scripts/feed-watch" check
        '');
      };
    };

    systemd.user.timers.feed-watch = {
      Unit = {
        Description = "Check GitHub feeds every 5 minutes";
      };
      Timer = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };
  }
