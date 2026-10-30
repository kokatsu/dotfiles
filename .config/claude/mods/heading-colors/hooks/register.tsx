import type { Color, Register } from 'claude-code';

const FENCE = /^ {0,3}(`{3,}|~{3,})(.*)$/;
const HEADING = /^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$/;

type Part = { markdown: string } | { level: number; title: string };

export function splitHeadings(text: string): Part[] {
  const parts: Part[] = [];
  let markdown: string[] = [];
  let fence: string | undefined;
  const flush = () => {
    const chunk = markdown
      .join('\n')
      .replace(/^\s*\n/, '')
      .trimEnd();
    if (chunk) parts.push({ markdown: chunk });
    markdown = [];
  };
  for (const line of text.split('\n')) {
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
    const heading = fence || open ? null : HEADING.exec(line);
    if (heading) {
      flush();
      const [, hashes = '', title = ''] = heading;
      parts.push({ level: hashes.length, title: plain(title) });
    } else {
      markdown.push(line);
    }
  }
  flush();
  return parts;
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

export const register: Register = (on) => {
  let bullet: Promise<string> | undefined;

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const parts = splitHeadings(e.props.text);
    if (!parts.some((p) => 'level' in p)) return next(e);

    const { Box, Text } = $.ui.resolve(e);

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
        const heading = (
          <Text color={COLORS[p.level] ?? 'warning'} bold>
            {p.title}
          </Text>
        );
        if (!isFirst) {
          return (
            <Box paddingLeft={2} marginTop={1}>
              {heading}
            </Box>
          );
        }
        // The engine draws no bullet for an empty block, so a reply that opens
        // with a heading draws its own, using the glyph the engine picks per OS.
        bullet ??= $.process
          .run(['uname'])
          .then((r) => (r.stdout.trim() === 'Darwin' ? '⏺' : '●'));
        return (
          <Box flexDirection="row" marginTop={1}>
            <Box width={2}>
              <Text color="text">{await bullet}</Text>
            </Box>
            {heading}
          </Box>
        );
      }),
    );
    return <Box flexDirection="column">{drawn}</Box>;
  }).catch((_$, e, next) => next(e));
};
