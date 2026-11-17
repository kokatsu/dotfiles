module.exports = (context) => ({
  [context.Syntax.Str](node) {
    const text = context.getSource(node);
    if (!/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/u.test(text))
      return;
    for (const match of text.matchAll(/[—–―⸺⸻]|──+/gu)) {
      context.report(
        node,
        new context.RuleError(
          '地の文のダッシュは句点、読点、丸括弧で書き換えてください。',
          {
            index: match.index,
          },
        ),
      );
    }
  },
});
