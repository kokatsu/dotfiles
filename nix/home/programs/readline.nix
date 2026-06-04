_: {
  programs.readline = {
    enable = true;
    variables = {
      bell-style = "none";
    };
    bindings = {
      # 入力済み文字列をプレフィックスとして履歴を遡る (psql 含む全 readline アプリ)
      "\\e[A" = "history-search-backward"; # ↑
      "\\e[B" = "history-search-forward"; # ↓
    };
  };
}
