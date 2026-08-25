{
  pkgs,
  lib,
  isWSL,
  ...
}:
lib.mkIf isWSL {
  systemd.user.services.disk-watch = {
    Unit = {
      Description = "Check disk usage for the WezTerm status bar";
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "disk-watch-check" ''
        export PATH="${lib.makeBinPath (with pkgs; [bash coreutils gawk jq])}"
        exec "$HOME/.local/bin/scripts/disk-watch" check
      '');
    };
  };

  systemd.user.timers.disk-watch = {
    Unit = {
      Description = "Check disk usage every 5 minutes";
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
