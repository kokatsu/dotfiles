{
  # merge.conflictStyle はこのモジュールが diff3 に固定する。zdiff3 は両側に共通する
  # 行を競合の外へ出すため、mergiraf が元の版を復元できず構文解析に失敗する
  programs.mergiraf = {
    enable = true;
    enableGitIntegration = true;
  };
}
