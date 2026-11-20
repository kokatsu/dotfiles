const { createRequire } = require('node:module');
// kuromojin is only installed nested under the presets, not on NODE_PATH.
const { tokenize } = createRequire(
  require.resolve('textlint-rule-preset-ja-technical-writing'),
)('kuromojin');

// A comma between two long modifiers is legitimate (Honda's first rule), so
// only short noun objects are flagged. An English word counts as one
// character so that `textlint の設定を、` is measured like `検査の設定を、`.
const MAX_OBJECT_LENGTH = 10;
const PRONOUN = /^(これ|それ|あれ|どれ|何|なに|誰|だれ|どこ|ここ|そこ)$/;
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

const isShortObjectComma = (tokens, i) => {
  let start = i;
  while (start > 0 && isNounPart(tokens[start - 1])) start--;
  const object = tokens.slice(start, i);
  const text = object.map((t) => t.surface_form).join('');
  const before = tokens[start - 1];
  // A、Bを、 and Aを、Bを、 are lists; 明日、設定を、 is not.
  const listed =
    before?.surface_form === '、' &&
    ((tokens[start - 2]?.pos === '名詞' &&
      tokens[start - 2].pos_detail_1 !== '副詞可能') ||
      is(tokens[start - 2], 'を'));
  if (
    object.length === 0 ||
    object[0].surface_form === 'の' ||
    text.replace(/[A-Za-z0-9_.-]+/g, 'x').length > MAX_OBJECT_LENGTH ||
    /[「」『』]/.test(text) ||
    PRONOUN.test(text) ||
    listed ||
    // 読んだ本を、 / AとBを、
    isPredicate(before) ||
    before?.surface_form === '・' ||
    before?.pos_detail_1 === '並立助詞'
  )
    return false;

  const next = phraseAfter(tokens, i + 1);
  return !next.some(
    (t, n) =>
      // Aを、Bを
      is(t, 'を') ||
      // 設定を、利用者が変える
      (t.pos_detail_1 === '係助詞' && t.surface_form === 'は') ||
      (t.pos_detail_1 === '格助詞' && t.surface_form === 'が') ||
      // 鍵を、なくした人に届けた: the comma keeps the object off the clause.
      (isPredicate(t) && next[n + 1]?.pos === '名詞'),
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
    else if (token.surface_form === 'を' && isShortObjectComma(tokens, i))
      message =
        '短い目的語の「を」の後の読点は間を作るだけなので外してください。';
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
