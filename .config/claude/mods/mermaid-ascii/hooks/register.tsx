import type { Register } from 'claude-code';

const FENCE = /^ {0,3}(`{3,}|~{3,})(.*)$/;

type Diagram = { start: number; end: number; source: string };

// Tracks every fence, not just mermaid ones: a mermaid fence quoted inside
// an outer fence is an example to copy, not a diagram to draw.
export function findDiagrams(text: string): Diagram[] {
  const diagrams: Diagram[] = [];
  let open:
    | { marker: string; start: number; body: number; isMermaid: boolean }
    | undefined;
  let at = 0;
  for (const line of text.split('\n')) {
    const lineEnd = at + line.length;
    const fence = FENCE.exec(line);
    if (fence) {
      const [, marker = '', info = ''] = fence;
      if (!open) {
        if (!(marker[0] === '`' && info.includes('`'))) {
          const isMermaid = info.trim().split(/\s/)[0] === 'mermaid';
          open = { marker, start: at, body: lineEnd + 1, isMermaid };
        }
      } else if (
        marker[0] === open.marker[0] &&
        marker.length >= open.marker.length &&
        info.trim() === ''
      ) {
        if (open.isMermaid) {
          const source = text.slice(open.body, at);
          diagrams.push({ start: open.start, end: lineEnd, source });
        }
        open = undefined;
      }
    }
    at = lineEnd + 1;
  }
  return diagrams;
}

// The transcript indents a reply past its bullet, so the full width would wrap.
const INDENT = 4;

export const register: Register = (on) => {
  // A streaming reply redraws on every flush; each diagram renders once.
  const cache = new Map<string, Promise<string | undefined>>();

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const { text } = e.props;
    const columns = e.viewport ? e.viewport.columns - INDENT : undefined;

    const toAscii = (source: string) => {
      const key = `${columns}\0${source}`;
      let ascii = cache.get(key);
      if (!ascii) {
        const width = columns ? ['--max-width', String(columns)] : [];
        ascii = $.process
          .run(['mermaid-ascii', '-f', '-', ...width], { stdin: source })
          .then((r) => (r.exitCode === 0 ? r.stdout.trimEnd() : undefined));
        cache.set(key, ascii);
      }
      return ascii;
    };

    const diagrams = findDiagrams(text);
    const rendered = await Promise.all(diagrams.map((d) => toAscii(d.source)));
    if (rendered.every((r) => r === undefined)) return next(e);

    const { Box, Text } = $.ui.resolve(e);
    const parts: Array<{ markdown: string } | { ascii: string }> = [];
    let markdown = '';
    let at = 0;
    diagrams.forEach((d, i) => {
      const ascii = rendered[i];
      if (ascii === undefined) return;
      markdown += text.slice(at, d.start);
      if (markdown.trim()) parts.push({ markdown });
      parts.push({ ascii });
      markdown = '';
      at = d.end;
    });
    markdown += text.slice(at);
    if (markdown.trim()) parts.push({ markdown });

    // Prose goes back through the engine so it keeps the reply's bullet and
    // spacing. Only the first block draws the bullet, and the engine indents no
    // block after it, so those take the bullet's width as padding.
    const drawn = await Promise.all(
      parts.map(async (p, i) => {
        if ('markdown' in p) {
          const isFirst = e.props.isFirstOfReply && i === 0;
          const prose = await next({
            ...e,
            props: {
              ...e.props,
              text: p.markdown.replace(/^\s*\n/, '').trimEnd(),
              isFirstOfReply: isFirst,
            },
          });
          return i === 0 ? prose : <Box paddingLeft={2}>{prose}</Box>;
        }
        return (
          <Box flexDirection="column" paddingLeft={2} marginTop={1}>
            {p.ascii.split('\n').map((line) => (
              <Text wrap="truncate-end">
                {runs(line).map((r) => (
                  <Text {...PAINT[r.kind]}>{r.text}</Text>
                ))}
              </Text>
            ))}
          </Box>
        );
      }),
    );
    return <Box flexDirection="column">{drawn}</Box>;
  }).catch((_$, e, next) => next(e));
};

type Kind = 'border' | 'arrow' | 'label';

const PAINT: Record<Kind, { color?: string; bold?: boolean }> = {
  border: { color: 'subtle' },
  arrow: { color: 'claude' },
  label: { bold: true },
};

function kindOf(ch: string): Kind {
  if (/[►◄▲▼]/.test(ch)) return 'arrow';
  return /[─-╿]/.test(ch) ? 'border' : 'label';
}

function runs(line: string): Array<{ kind: Kind; text: string }> {
  const out: Array<{ kind: Kind; text: string }> = [];
  for (const ch of line) {
    const kind = ch === ' ' ? (out.at(-1)?.kind ?? 'label') : kindOf(ch);
    const last = out.at(-1);
    if (last?.kind === kind) last.text += ch;
    else out.push({ kind, text: ch });
  }
  return out;
}
