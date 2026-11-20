const { createRequire } = require('node:module');
// kuromojin is only installed nested under the presets, not on NODE_PATH.
const { tokenize } = createRequire(
  require.resolve('textlint-rule-preset-ja-technical-writing'),
)('kuromojin');

// These split into a noun and 格助詞 に but read as sentence adverbs or a
// compound particle (をもとに), like the single-token 次に and さらに.
const ADVERBIAL_NI = /^(最初|最後|代わり|逆|一般|同様|反対|もと)$/;
const isAdverbial = (t) =>
  ['非自立', '副詞可能', '数'].includes(t.pos_detail_1) ||
  ADVERBIAL_NI.test(t.surface_form);
// Inline code stands in as one noun, so `a.json` と、`b.json` を is seen.
const CODE_PLACEHOLDER = 'コード';

const isPredicate = (t) =>
  t?.pos === '動詞' || t?.pos === '助動詞' || t?.pos === '形容詞';
const isNounPart = (t) =>
  t?.pos === '名詞' ||
  t?.pos === '接頭詞' ||
  t?.pos === '連体詞' ||
  (t?.pos === '助詞' && t.surface_form === 'の');
const isBoundary = (t) => /[。！？!?\n]/.test(t.surface_form);
const is = (t, surface) => t?.pos === '助詞' && t.surface_form === surface;

// Tokens from the comma to the next comma or sentence end.
const phraseAfter = (tokens, comma) => {
  let end = comma + 1;
  while (
    end < tokens.length &&
    tokens[end].surface_form !== '、' &&
    !isBoundary(tokens[end])
  )
    end++;
  return tokens.slice(comma + 1, end);
};

// A second noun phrase must follow, so 完了と、報告した is left alone.
// Quotative と before a noun (原因は設定ミスと、担当者が報告した) has the
// same shape and is flagged too, so the message also covers rewording it.
// A phrase without a predicate (Aと、Bまでの案内の設計, a table cell or a
// title) can only be the second item of the list.
const isCoordinationComma = (tokens, i) => {
  if (tokens[i - 1]?.pos !== '名詞') return false;
  const next = phraseAfter(tokens, i + 1);
  let k = 0;
  while (isNounPart(next[k])) k++;
  const particle = next[k];
  return (
    k > 0 &&
    ((particle?.pos === '助詞' &&
      particle.pos_detail_2 !== '引用' &&
      ['格助詞', '並立助詞', '係助詞'].includes(particle.pos_detail_1)) ||
      !next.some(isPredicate))
  );
};

// 設定を、 and 設定に、 are flagged whatever the length of the noun phrase.
// The comma stays where it marks a boundary the reader needs: another subject,
// a list, or a clause the object would otherwise attach to.
const isCaseComma = (tokens, i) => {
  const particle = tokens[i].surface_form;
  const head = tokens[i - 1];
  if (
    head?.pos !== '名詞' ||
    head.pos_detail_1 === '代名詞' ||
    tokens[i].pos_detail_1 !== '格助詞'
  )
    return false;
  // 読めるように、 / 失敗したときに、 / 処理の前に、 / 第一に、 / 最後に、
  if (particle === 'に' && isAdverbial(head)) return false;

  const next = phraseAfter(tokens, i + 1);
  // Only を makes a list (A、Bを、 and Aを、Bを、), and only when the phrase
  // after the comma is closed by another comma (設定を、値を見て直す is
  // not one). Repeated に cannot be told apart by part of speech:
  // 画面に、縦に、 has the shape of 設定に、ログに、 with different roles.
  if (particle === 'を') {
    let start = i;
    while (start > 0 && isNounPart(tokens[start - 1])) start--;
    // 明日、設定を、 is not a list.
    if (
      tokens[start - 1]?.surface_form === '、' &&
      ((tokens[start - 2]?.pos === '名詞' &&
        tokens[start - 2].pos_detail_1 !== '副詞可能') ||
        is(tokens[start - 2], particle))
    )
      return false;
    let k = 0;
    while (isNounPart(next[k])) k++;
    if (
      k > 0 &&
      k === next.length - 1 &&
      is(next[k], particle) &&
      tokens[i + 3 + k]?.surface_form === '、'
    )
      return false;
  }
  return !next.some(
    (t, n) =>
      // 設定を、利用者が変える
      (t.pos_detail_1 === '係助詞' && t.surface_form === 'は') ||
      (t.pos_detail_1 === '格助詞' && t.surface_form === 'が') ||
      // 鍵を、なくした人に届けた: the comma keeps the object off the clause.
      ((t.pos === '動詞' || t.pos === '助動詞') && next[n + 1]?.pos === '名詞'),
  );
};

// Plain text of a block with emphasis and links unwrapped, so a sentence is
// analysed whole, plus where each Str's text sits in the source.
const flatten = (context, node, out = { text: '', segments: [] }) => {
  for (const child of node.children ?? []) {
    if (child.type === 'Str') {
      out.segments.push({ plain: out.text.length, source: child.range[0] });
      out.text += context.getSource(child);
    } else if (child.type === 'Code') {
      out.text += CODE_PLACEHOLDER;
    } else if (child.children) {
      flatten(context, child, out);
    } else {
      out.text += '\n';
    }
  }
  return out;
};

const check = async (context, node) => {
  const { text, segments } = flatten(context, node);
  if (!text.includes('、')) return;
  let offset = 0;
  const tokens = [];
  for (const token of await tokenize(text)) {
    // word_position counts code points; source offsets are UTF-16 units.
    token.offset = offset;
    offset += token.surface_form.length;
    if (token.pos_detail_1 !== '空白' || isBoundary(token)) tokens.push(token);
  }
  tokens.forEach((token, i) => {
    if (tokens[i + 1]?.surface_form !== '、' || token.pos !== '助詞') return;
    let message;
    if (
      token.surface_form === 'と' &&
      token.pos_detail_1 !== '接続助詞' &&
      isCoordinationComma(tokens, i)
    )
      message =
        '「と」の後に読点を打たないでください。並列の「AとB」なら読点を外し、引用の「と」で読点を外すと誤読される場合は語順を入れ替えてください。';
    else if (
      (token.surface_form === 'を' || token.surface_form === 'に') &&
      isCaseComma(tokens, i)
    )
      message = `「${token.surface_form}」の後の読点は間を作るだけなので外してください。掛かり先が曖昧になる場合は語順を入れ替えてください。`;
    if (!message) return;
    const plain = tokens[i + 1].offset;
    const segment = segments.findLast((s) => s.plain <= plain);
    const index = segment.source + plain - segment.plain - node.range[0];
    context.report(node, new context.RuleError(message, { index }));
  });
};

module.exports = (context) => ({
  [context.Syntax.Paragraph]: (node) => check(context, node),
  [context.Syntax.Header]: (node) => check(context, node),
  [context.Syntax.TableCell]: (node) => check(context, node),
});
