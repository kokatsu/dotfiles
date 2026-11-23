# 日本語の文書差分を 1 文字単位で強調するパッチを当てる。
# 上流の単語分割は漢字・かなの連続を 1 単語とみなし、1 文字の変更でも句読点までを丸ごと強調する。
{
  difftastic-cjk-words = _final: prev: {
    difftastic = prev.difftastic.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./patches/difftastic-cjk-words.patch];
    });
  };
}
