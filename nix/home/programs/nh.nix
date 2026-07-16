# 参考: https://zenn.dev/trifolium/articles/ed53f1a6ebbbf8
{
  config,
  lib,
  ...
}: let
  cleanArgs = ["--keep-since" "30d" "--keep-one"];
in {
  programs.nh = {
    enable = true;
    # 不要なNixストアを自動削除 (週1回、直近30日と各profileの最新1世代は残す)
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = lib.concatStringsSep " " cleanArgs;
    };
  };

  # Home Manager の nh モジュールは launchd に extraArgs 全体を argv の 1 要素として
  # 渡すため、macOS では毎回パースエラー (exit 2) で失敗する。フラグを個別要素に
  # 分割して上書きする (launchd は macOS のみ有効なので Linux には影響しない)
  launchd.agents.nh-clean.config.ProgramArguments = lib.mkForce ([
      (lib.getExe config.programs.nh.package)
      "clean"
      "user"
    ]
    ++ cleanArgs);
}
