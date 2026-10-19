// `ApiMessage` is not exported by 'claude-code', so the shape is restated here.
export type Block = { type: string; [field: string]: unknown };
export type Message = {
  role: "user" | "assistant";
  content: readonly Block[];
};

export const EARLIER_CHARS = 2000;

const REMINDER = "<system-reminder>";
const STOP_FEEDBACK = "Stop hook feedback:";

function clip(text: string, limit: number | undefined): string {
  if (limit === undefined || text.length <= limit) return text;
  return `${text.slice(0, limit)}\n[... ${
    text.length - limit
  } more chars truncated]`;
}

function textOf(block: Block): string {
  return typeof block.text === "string" ? block.text : "";
}

// The harness wraps everything it injects in <system-reminder>, so an unwrapped
// text block in a message without tool results is what the person typed.
function isPrompt(m: Message): boolean {
  return m.role === "user" &&
    !m.content.some((b) => b.type === "tool_result") &&
    m.content.some((b) => {
      const text = textOf(b).trimStart();
      return b.type === "text" && text !== "" &&
        !text.startsWith(REMINDER) && !text.startsWith(STOP_FEEDBACK);
    });
}

export function latestTurnStart(messages: readonly Message[]): number {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m !== undefined && isPrompt(m)) return i;
  }
  return 0;
}

function resultText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((b: Block) =>
    b.type === "text" ? textOf(b) : `[${b.type}]`
  )
    .join("\n");
}

type ToolUse = { name: string; input: unknown };

function renderAnswer(m: Message): string[] {
  return m.content.flatMap((b) => {
    const text = textOf(b);
    return b.type === "text" && text.trim() !== ""
      ? [`[assistant]\n${text}`]
      : [];
  });
}

function render(
  m: Message,
  uses: ReadonlyMap<string, ToolUse>,
  limit: number | undefined,
): string[] {
  if (m.role === "assistant") return [];
  return m.content.flatMap((b) => {
    if (b.type === "text") {
      const text = textOf(b);
      const trimmed = text.trimStart();
      if (trimmed === "") return [];
      const injected = trimmed.startsWith(REMINDER) ||
        trimmed.startsWith(STOP_FEEDBACK);
      return [`${injected ? "[context]" : "[user]"}\n${text}`];
    }
    if (b.type === "tool_result") {
      const use = uses.get(String(b.tool_use_id));
      return [[
        `[tool ${use?.name ?? "unknown"}${b.is_error ? " (error)" : ""}]`,
        `input: ${clip(JSON.stringify(use?.input ?? null), limit)}`,
        `output:\n${clip(resultText(b.content), limit)}`,
      ].join("\n")];
    }
    return [`[${b.type}]`];
  });
}

// The prompt cache matches only a prefix that ends where a block ended in an
// earlier request, so each earlier turn is its own block: the next judgment
// appends one block and finds the previous breakpoint one block back.
export function buildEvidence(
  messages: readonly Message[],
): { earlier: string[]; latest: string; text: string; latestChars: number } {
  const uses = new Map<string, ToolUse>();
  for (const m of messages) {
    for (const b of m.content) {
      if (b.type === "tool_use") {
        uses.set(String(b.id), { name: String(b.name), input: b.input });
      }
    }
  }
  const start = latestTurnStart(messages);
  const turns: string[][] = [];
  for (const m of messages.slice(0, start)) {
    if (turns.length === 0 || isPrompt(m)) turns.push([]);
    turns.at(-1)?.push(
      ...(m.role === "assistant"
        ? renderAnswer(m)
        : render(m, uses, EARLIER_CHARS)),
    );
  }
  const earlier = [
    `## Earlier turns (tool inputs and outputs truncated to ${EARLIER_CHARS} chars each; [user], [assistant] and [context] are whole)`,
    ...turns.filter((t) => t.length > 0).map((t) => t.join("\n\n")),
  ];
  const latestText = messages.slice(start).flatMap((m) =>
    render(m, uses, undefined)
  ).join("\n\n");
  const latest = ["## Latest turn (complete)", latestText].join("\n\n");
  return {
    earlier,
    latest,
    text: [...earlier, latest].join("\n\n"),
    latestChars: latestText.length,
  };
}
