import type { Color, Register } from 'claude-code';

const FENCE = /^ {0,3}(`{3,}|~{3,})(.*)$/;
const HEADING = /^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$/;
const LIST = /^( *)([-*+]|\d{1,9}[.)])[ \t]+(\S.*)$/;
// Lines a paragraph cannot start with: quotes, tables, rules, setext
// underlines, indented code and HTML.
const BLOCK = /^(?: {4}|\t| {0,3}(?:[>|<=]|[-*_](?:[ \t]*[-*_]){2,}[ \t]*$))/;

type Run = { text: string; isStrong: boolean };
type Item = { indent: number; marker: string; text: string };
type Part =
  | { markdown: string }
  | { level: number; title: string }
  | { items: Item[] }
  | { runs: Run[] };

const isBlank = (line: string | undefined) => !line?.trim();

export function parse(text: string): Part[] {
  const lines = text.split('\n');
  const parts: Part[] = [];
  let markdown: string[] = [];
  let fence: string | undefined;
  // Whether the line before ends a block, so the next line starts a new one.
  let isBoundary = true;
  // Lines up to here belong to a list left whole to the engine.
  let engineUntil = 0;
  const flush = () => {
    const chunk = markdown
      .join('\n')
      .replace(/^\s*\n/, '')
      .trimEnd();
    if (chunk) parts.push({ markdown: chunk });
    markdown = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? '';
    const open = FENCE.exec(line);
    if (open) {
      const [, marker = '', info = ''] = open;
      if (!fence) {
        if (!(marker[0] === '`' && info.includes('`'))) fence = marker;
      } else if (
        marker[0] === fence[0] &&
        marker.length >= fence.length &&
        info.trim() === ''
      ) {
        fence = undefined;
      }
    }
    if (fence || open) {
      markdown.push(line);
      isBoundary = false;
      continue;
    }

    const heading = HEADING.exec(line);
    if (heading) {
      flush();
      const [, hashes = '', title = ''] = heading;
      parts.push({ level: hashes.length, title: plain(title) });
      isBoundary = true;
      continue;
    }

    const list = i < engineUntil ? undefined : listAt(lines, i, isBoundary);
    if (list?.items) {
      flush();
      parts.push({ items: list.items });
      i = list.end - 1;
      isBoundary = true;
      continue;
    }
    if (list) engineUntil = list.end;
    if (i < engineUntil) {
      markdown.push(line);
      isBoundary = false;
      continue;
    }

    const runs =
      isBoundary &&
      !BLOCK.test(line) &&
      !LIST.test(line) &&
      endsParagraph(lines[i + 1])
        ? strongRuns(line)
        : undefined;
    if (runs) {
      flush();
      parts.push({ runs });
      isBoundary = true;
      continue;
    }

    markdown.push(line);
    isBoundary = isBlank(line);
  }
  flush();
  return parts;
}

// CommonMark: only an unordered list or one starting at 1 interrupts a
// paragraph.
const INTERRUPTS = /^ *(?:[-*+]|1[.)])[ \t]+\S/;

function endsParagraph(next: string | undefined): boolean {
  return (
    isBlank(next) || INTERRUPTS.test(next ?? '') || HEADING.test(next ?? '')
  );
}

// A run of list lines with nothing that belongs to an item beyond its first
// line. Continuation lines, lazy or indented, leave the whole list to the
// engine (no `items`), so one list is never drawn half by each.
function listAt(
  lines: string[],
  start: number,
  isBoundary: boolean,
): { items?: Item[]; end: number } | undefined {
  const items: Item[] = [];
  let end = start;
  for (; end < lines.length; end++) {
    const m = LIST.exec(lines[end] ?? '');
    if (!m) break;
    const [, indent = '', marker = '', text = ''] = m;
    items.push({ indent: indent.length, marker, text });
  }
  const [first] = items;
  if (!first) return undefined;
  if (!isBoundary && !INTERRUPTS.test(lines[start] ?? '')) return undefined;
  const after = (from: number) => {
    let at = from;
    while (at < lines.length && isBlank(lines[at])) at++;
    return at;
  };
  if (isBlank(lines[end]) && !/^[ \t]/.test(lines[after(end)] ?? '')) {
    return { items, end };
  }
  for (;;) {
    while (end < lines.length && !isBlank(lines[end])) end++;
    const next = lines[after(end)] ?? '';
    if (!/^[ \t]/.test(next) && !LIST.test(next)) return { end };
    end = after(end);
  }
}

// The line split at `**` pairs, or undefined when it holds any other markdown
// the engine would draw: a Text cannot draw it, so the engine keeps the line.
export function strongRuns(line: string): Run[] | undefined {
  if (/[`[\]<>~_\\|]|&#?\w+;|:\/\/|www\./.test(line)) return undefined;
  const runs: Run[] = [];
  let at = 0;
  for (const m of line.matchAll(/\*\*([^*\s](?:[^*]*[^*\s])?)\*\*/g)) {
    runs.push({ text: line.slice(at, m.index), isStrong: false });
    runs.push({ text: m[1] ?? '', isStrong: true });
    at = m.index + m[0].length;
  }
  runs.push({ text: line.slice(at), isStrong: false });
  const rest = runs.filter((r) => !r.isStrong).map((r) => r.text);
  if (runs.length === 1 || rest.some((t) => t.includes('*'))) return undefined;
  return runs.filter((r) => r.text);
}

// CommonMark: a code span closes on a backtick run of the same length as the
// one that opened it.
const CODE_SPAN = /(?<!`)(`+)(?!`)(.*?[^`])\1(?!`)/g;

// A Text draws no markdown, so the heading's inline marks would show as written.
function plain(title: string): string {
  let out = '';
  let at = 0;
  for (const m of title.matchAll(CODE_SPAN)) {
    const [span, , code = ''] = m;
    const isPadded = code.startsWith(' ') && code.endsWith(' ') && code.trim();
    out +=
      unmark(title.slice(at, m.index)) + (isPadded ? code.slice(1, -1) : code);
    at = m.index + span.length;
  }
  return out + unmark(title.slice(at));
}

function unmark(s: string): string {
  return s
    .replace(/(\*\*|__|~~)(.+?)\1/g, '$2')
    .replace(/\*(.+?)\*/g, '$1')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
}

const COLORS: Record<number, Color> = {
  1: 'claude',
  2: 'ide',
  3: 'success',
};
const STRONG: Color = 'merged';
const MARKER: Color = 'planMode';

export const register: Register = (on) => {
  let bullet: Promise<string> | undefined;

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const parts = parse(e.props.text);
    if (parts.every((p) => 'markdown' in p)) return next(e);

    const { Box, Text, Markdown } = $.ui.resolve(e);
    const strong = (runs: Run[]) => (
      <Text>
        {runs.map((r) =>
          r.isStrong ? (
            <Text color={STRONG} bold>
              {r.text}
            </Text>
          ) : (
            r.text
          ),
        )}
      </Text>
    );

    // Same layout as mermaid-ascii: only the first block carries the bullet,
    // so later blocks take its width as padding.
    const drawn = await Promise.all(
      parts.map(async (p, i) => {
        const isFirst = e.props.isFirstOfReply && i === 0;
        if ('markdown' in p) {
          const prose = await next({
            ...e,
            props: { ...e.props, text: p.markdown, isFirstOfReply: isFirst },
          });
          return i === 0 ? prose : <Box paddingLeft={2}>{prose}</Box>;
        }
        const block =
          'level' in p ? (
            <Text color={COLORS[p.level] ?? 'warning'} bold>
              {p.title}
            </Text>
          ) : 'runs' in p ? (
            strong(p.runs)
          ) : (
            <Box flexDirection="column">
              {p.items.map((item) => {
                const runs = strongRuns(item.text);
                return (
                  <Box flexDirection="row" paddingLeft={item.indent}>
                    <Box flexShrink={0}>
                      <Text color={MARKER}>{`${item.marker} `}</Text>
                    </Box>
                    <Box flexGrow={1} flexShrink={1}>
                      {runs ? strong(runs) : <Markdown text={item.text} />}
                    </Box>
                  </Box>
                );
              })}
            </Box>
          );
        if (!isFirst) {
          return (
            <Box paddingLeft={2} marginTop={1}>
              {block}
            </Box>
          );
        }
        // The engine draws no bullet for an empty block, so a reply that opens
        // with a block of ours draws its own, using the glyph the engine picks
        // per OS.
        bullet ??= $.process
          .run(['uname'])
          .then((r) => (r.stdout.trim() === 'Darwin' ? '⏺' : '●'));
        return (
          <Box flexDirection="row" marginTop={1}>
            <Box width={2}>
              <Text color="text">{await bullet}</Text>
            </Box>
            {block}
          </Box>
        );
      }),
    );
    return <Box flexDirection="column">{drawn}</Box>;
  }).catch((_$, e, next) => next(e));
};
