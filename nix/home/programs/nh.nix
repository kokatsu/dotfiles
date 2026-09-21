# 参考: https://zenn.dev/trifolium/articles/ed53f1a6ebbbf8
{config, ...}: let
  cleanArgs = ["--keep-since" "30d" "--keep-one"];
in {
  programs.nh = {
    enable = true;
    # 不要なNixストアを自動削除 (週1回、直近30日と各profileの最新1世代は残す)
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = cleanArgs;
    };
  };

  # Home Manager の nh モジュールは systemd unit / launchd agent に PATH を設定しない。
  # NixOS なら user manager の PATH に /run/current-system/sw/bin が入るが、standalone HM
  # では distro 既定の PATH のままなので nh が nix を見つけられず毎回失敗する。
  # Linux (single-user Nix) は profile の nix、macOS (Determinate Nix) は
  # /nix/var/nix/profiles/default の nix を指す。
  systemd.user.services.nh-clean.Service.Environment = [
    "PATH=${config.home.homeDirectory}/.nix-profile/bin"
  ];
  launchd.agents.nh-clean.config = {
    EnvironmentVariables.PATH = "/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
    # launchd は失敗しても痕跡を残さないので出力をファイルに落とす
    StandardOutPath = "${config.home.homeDirectory}/Library/Logs/nh-clean.log";
    StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/nh-clean.log";
  };
}
