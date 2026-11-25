// deno-lint-ignore-file jsx-key -- the mod JSX factory (h) is not React and has no keys
import type { Color, Register } from "claude-code";

const FENCE = /^ {0,3}(`{3,}|~{3,})(.*)$/;
const HEADING = /^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$/;
const LIST = /^( *)([-*+]|\d{1,9}[.)])[ \t]+(\S.*)$/;
// Lines a paragraph cannot start with: quotes, tables, rules, setext
// underlines, indented code and HTML.
const BLOCK = /^(?: {4}|\t| {0,3}(?:[>|<=]|[-*_](?:[ \t]*[-*_]){2,}[ \t]*$))/;

type Run = { text: string; isStrong?: true; isCode?: true };
type Item = { indent: number; marker: string; text: string };
type Part =
  | { markdown: string }
  | { level: number; title: string }
  | { items: Item[] }
  | { runs: Run[] };

const isBlank = (line: string | undefined) => !line?.trim();

export function parse(text: string): Part[] {
  const lines = text.split("\n");
  const parts: Part[] = [];
  let markdown: string[] = [];
  let fence: string | undefined;
  // Whether the line before ends a block, so the next line starts a new one.
  let isBoundary = true;
  // Lines up to here belong to a list left whole to the engine.
  let engineUntil = 0;
  const flush = () => {
    const chunk = markdown
      .join("\n")
      .replace(/^\s*\n/, "")
      .trimEnd();
    if (chunk) parts.push({ markdown: chunk });
    markdown = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? "";
    const open = FENCE.exec(line);
    if (open) {
      const [, marker = "", info = ""] = open;
      if (!fence) {
        if (!(marker[0] === "`" && info.includes("`"))) fence = marker;
      } else if (
        marker[0] === fence[0] &&
        marker.length >= fence.length &&
        info.trim() === ""
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
      const [, hashes = "", title = ""] = heading;
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

    const runs = isBoundary &&
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
    isBlank(next) || INTERRUPTS.test(next ?? "") || HEADING.test(next ?? "")
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
    const m = LIST.exec(lines[end] ?? "");
    if (!m) break;
    const [, indent = "", marker = "", text = ""] = m;
    items.push({ indent: indent.length, marker, text });
  }
  const [first] = items;
  if (!first) return undefined;
  if (!isBoundary && !INTERRUPTS.test(lines[start] ?? "")) return undefined;
  const after = (from: number) => {
    let at = from;
    while (at < lines.length && isBlank(lines[at])) at++;
    return at;
  };
  if (isBlank(lines[end]) && !/^[ \t]/.test(lines[after(end)] ?? "")) {
    return { items, end };
  }
  for (;;) {
    while (end < lines.length && !isBlank(lines[end])) end++;
    const next = lines[after(end)] ?? "";
    if (!/^[ \t]/.test(next) && !LIST.test(next)) return { end };
    end = after(end);
  }
}

// CommonMark: a code span closes on a backtick run of the same length as the
// one that opened it.
const CODE_SPAN = /(?<!`)(`+)(?!`)(.*?[^`])\1(?!`)/g;

function unpad(code: string): string {
  const isPadded = /^ .*[^ ].* $/.test(code);
  return isPadded ? code.slice(1, -1) : code;
}

// Stands in for a code span, so that its content is not read as markdown.
const MASK = "\0";

// CommonMark: `**` with punctuation on its inner side is a delimiter only when
// whitespace, punctuation or the line's edge is on its outer side. A masked
// code span counts as punctuation, for its backticks.
function isDelimiter(inner = "", outer = ""): boolean {
  const isPunctuation = (c: string) => c === MASK || /[\p{P}\p{S}]/u.test(c);
  return !isPunctuation(inner) || !outer.trim() || isPunctuation(outer);
}

// The line split at `**` pairs and code spans, or undefined when it has no
// `**` pair or holds any other markdown the engine would draw: a Text cannot
// draw it, so the engine keeps the line.
export function strongRuns(line: string): Run[] | undefined {
  const codes: string[] = [];
  const masked = line.replace(CODE_SPAN, (_span, _ticks, code: string) => {
    codes.push(unpad(code));
    return MASK;
  });
  if (/[`[\]<>~_\\|]|&#?\w+;|:\/\/|www\./.test(masked)) return undefined;

  const runs: Run[] = [];
  const add = (text: string, isStrong?: true) => {
    text.split(MASK).forEach((prose, i) => {
      if (i > 0) {
        runs.push({
          text: codes.shift() ?? "",
          isCode: true,
          ...(isStrong && { isStrong }),
        });
      }
      if (prose) runs.push({ text: prose, ...(isStrong && { isStrong }) });
    });
  };
  let at = 0;
  let rest = "";
  for (const m of masked.matchAll(/\*\*([^*\s](?:[^*]*[^*\s])?)\*\*/g)) {
    const [pair, strong = ""] = m;
    const end = m.index + pair.length;
    const before = masked.slice(at, m.index);
    const last = (text: string) => text.match(/.$/u)?.[0];
    const [first] = strong;
    const [next] = masked.slice(end);
    if (
      !isDelimiter(first, last(masked.slice(0, m.index))) ||
      !isDelimiter(last(strong), next)
    ) return undefined;
    rest += before;
    add(before);
    add(strong, true);
    at = end;
  }
  const tail = masked.slice(at);
  add(tail);
  if (at === 0 || (rest + tail).includes("*")) return undefined;
  return runs;
}

// A Text draws no markdown, so the heading's inline marks would show as written.
function plain(title: string): string {
  let out = "";
  let at = 0;
  for (const m of title.matchAll(CODE_SPAN)) {
    const [span, , code = ""] = m;
    out += unmark(title.slice(at, m.index)) + unpad(code);
    at = m.index + span.length;
  }
  return out + unmark(title.slice(at));
}

function unmark(s: string): string {
  return s
    .replace(/(\*\*|__|~~)(.+?)\1/g, "$2")
    .replace(/\*(.+?)\*/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1");
}

const COLORS: Record<number, Color> = {
  1: "claude",
  2: "ide",
  3: "success",
};
const STRONG: Color = "merged";
const CODE: Color = "permission";
const MARKER: Color = "planMode";

export const register: Register = (on) => {
  let bullet: Promise<string> | undefined;

  on("ui.render", { component: "AssistantMessage" }, async ($, e, next) => {
    const parts = parse(e.props.text);
    if (parts.every((p) => "markdown" in p)) return next(e);

    const { Box, Text, Markdown } = $.ui.resolve(e);
    const strong = (runs: Run[]) => (
      <Text>
        {runs.map((r) =>
          r.isStrong || r.isCode
            ? (
              <Text color={r.isCode ? CODE : STRONG} bold={!!r.isStrong}>
                {r.text}
              </Text>
            )
            : (
              r.text
            )
        )}
      </Text>
    );

    // Same layout as mermaid-ascii: only the first block carries the bullet,
    // so later blocks take its width as padding.
    const drawn = await Promise.all(
      parts.map(async (p, i) => {
        const isFirst = e.props.isFirstOfReply && i === 0;
        if ("markdown" in p) {
          const prose = await next({
            ...e,
            props: { ...e.props, text: p.markdown, isFirstOfReply: isFirst },
          });
          return i === 0 ? prose : <Box paddingLeft={2}>{prose}</Box>;
        }
        const block = "level" in p
          ? (
            <Text color={COLORS[p.level] ?? "warning"} bold>
              {p.title}
            </Text>
          )
          : "runs" in p
          ? (
            strong(p.runs)
          )
          : (
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
        if (!bullet) {
          bullet = $.session
            .machine()
            .then((m) => (m.sysname === "Darwin" ? "⏺" : "●"));
          bullet.catch(() => {
            bullet = undefined;
          });
        }
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
