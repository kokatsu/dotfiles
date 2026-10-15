import { type Entry, rec } from "./feed-entries.ts";

export const TARGETS = [
  "Facebook Developers",
  "Recent Commits to docs:main",
  "X Developers - Latest topics",
  "Social Media Today",
];
export const MODEL = "gpt-6.1-sol";
export const MAX_INPUT = 128 * 1024;
export const MAX_BODY = 48 * 1024;
export type Confidence = "official" | "reported" | "uncertain";
export interface Input extends Entry {
  body: string;
  context_complete: boolean;
  limitations: string[];
}
export interface Decision {
  id: string;
  decision: "include" | "skip";
  reason: string;
  confidence: Confidence;
  group_id: string | null;
}
export interface Group {
  group_id: string;
  item_ids: string[];
  title: string;
  change: string;
  impact: string;
  action: string;
  confidence_note: string;
}
export interface Result {
  items: Decision[];
  groups: Group[];
}
export interface SavedItem extends Omit<Input, "body"> {
  decision: "include" | "skip" | "unavailable" | "manual";
  reason: string;
  confidence: Confidence;
  group_id: string | null;
}
export interface Receipt {
  version: 1;
  kind: "summary" | "reset";
  feed: string;
  category: string;
  start: string;
  end: string;
  batch_id: string;
  created_at: string;
  prompt_hash: string;
  model: string;
  items: SavedItem[];
  groups: Group[];
  warnings: string[];
}

const encoder = new TextEncoder();
export const bytes = (s: string) => encoder.encode(s).length;
export function clip(s: string, limit: number): string {
  return new TextDecoder().decode(encoder.encode(s).subarray(0, limit), {
    stream: true,
  });
}
export function limitInput(item: Input): Input {
  if (bytes(item.id) + bytes(item.link) > 32 * 1024) {
    throw new Error("entry identity exceeds input limit");
  }
  const next = { ...item, title: clip(item.title, 4096) };
  const limitations = item.limitations.slice(0, 20).map((s) => clip(s, 400));
  if (
    limitations.length !== item.limitations.length ||
    limitations.some((s, i) => s !== item.limitations[i])
  ) {
    limitations.push("省略理由の一覧も入力上限で一部省略");
  }
  next.limitations = limitations;
  next.body = clip(item.body, MAX_BODY);
  if (next.title !== item.title || next.body !== item.body) {
    next.context_complete = false;
    next.limitations.push("入力サイズの上限で資料を省略");
  }
  return next;
}
export async function hash(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(JSON.stringify(value)),
  );
  return Array.from(
    new Uint8Array(digest),
    (n) => n.toString(16).padStart(2, "0"),
  )
    .join("");
}
export async function feedKey(name: string): Promise<string> {
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "").slice(0, 45) || "feed";
  return `${slug}-${(await hash(name)).slice(0, 12)}`;
}
export function segment(name: string): string {
  return encodeURIComponent(name).replaceAll(".", "%2E") || "Uncategorized";
}
export function pending(entries: Entry[], last: string, github: boolean) {
  const index = entries.findIndex((e) => e.id === last);
  if (github && index < 0) {
    throw new Error("GitHub progress boundary not found");
  }
  const items = entries.slice(0, index < 0 ? undefined : index).reverse();
  const ids = new Set<string>();
  for (const e of items) {
    if (!e.id || ids.has(e.id)) throw new Error("empty or duplicate entry ID");
    ids.add(e.id);
  }
  const warnings = index < 0 && entries.length
    ? [
      `履歴欠落の可能性: 以前の境界 ID=${last}。取得範囲=${
        entries.at(-1)!.date || "日付不明"
      }〜${entries[0].date || "日付不明"}。欠落件数は不明です。`,
    ]
    : [];
  return { items, warnings };
}

function object(value: unknown, keys: string[]): Record<string, unknown> {
  const o = rec(value);
  if (!o || Object.keys(o).sort().join() !== [...keys].sort().join()) {
    throw new Error("unexpected response fields");
  }
  return o;
}
function nonempty(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}
export function validateResult(
  inputs: Pick<Input, "id">[],
  value: unknown,
): Result {
  const o = object(value, ["items", "groups"]);
  if (!Array.isArray(o.items) || !Array.isArray(o.groups)) {
    throw new Error("response arrays missing");
  }
  const expected = new Set(inputs.map((i) => i.id));
  if (expected.size !== inputs.length) throw new Error("duplicate input ID");
  const seen = new Set<string>();
  for (const value of o.items) {
    const i = object(value, [
      "id",
      "decision",
      "reason",
      "confidence",
      "group_id",
    ]);
    if (
      !nonempty(i.id) || !expected.has(i.id) || seen.has(i.id) ||
      !["include", "skip"].includes(String(i.decision)) ||
      !nonempty(i.reason) ||
      !["official", "reported", "uncertain"].includes(String(i.confidence)) ||
      (i.decision === "skip" ? i.group_id !== null : !nonempty(i.group_id))
    ) throw new Error("invalid decision or entry coverage");
    seen.add(i.id);
  }
  if (seen.size !== expected.size) throw new Error("missing decisions");
  const decisions = o.items as Decision[];
  const grouped = new Set<string>();
  const groupIds = new Set<string>();
  for (const value of o.groups) {
    const g = object(value, [
      "group_id",
      "item_ids",
      "title",
      "change",
      "impact",
      "action",
      "confidence_note",
    ]);
    if (
      !nonempty(g.group_id) || groupIds.has(g.group_id) ||
      !Array.isArray(g.item_ids) || !g.item_ids.length ||
      ![g.title, g.change, g.impact, g.action, g.confidence_note].every(
        nonempty,
      )
    ) throw new Error("invalid group");
    groupIds.add(g.group_id);
    for (const id of g.item_ids) {
      const d = decisions.find((i) => i.id === id);
      if (
        !d || d.decision !== "include" || d.group_id !== g.group_id ||
        grouped.has(id)
      ) {
        throw new Error("invalid group membership");
      }
      grouped.add(id);
    }
  }
  if (decisions.some((d) => d.decision === "include" && !grouped.has(d.id))) {
    throw new Error("ungrouped include");
  }
  return { items: decisions, groups: o.groups as Group[] };
}
export function groupConfidence(items: SavedItem[]): Confidence {
  return items.some((i) => i.confidence === "uncertain")
    ? "uncertain"
    : items.some((i) => i.confidence === "reported")
    ? "reported"
    : "official";
}
const line = (s: string) => s.replace(/[\r\n]+/g, " ").replace(/[<>]/g, "");
export function render(receipt: Receipt): string | null {
  if (
    !receipt.groups.length && !receipt.warnings.length &&
    receipt.kind !== "reset"
  ) return null;
  const output = [
    `# ${line(receipt.feed)}`,
    "",
    `- Date: ${receipt.created_at}`,
    "",
  ];
  if (receipt.warnings.length) {
    output.push(
      "## 警告",
      "",
      ...receipt.warnings.map((w) => `- ${line(w)}`),
      "",
    );
  }
  for (const g of receipt.groups) {
    const sources = g.item_ids.map((id) =>
      receipt.items.find((i) => i.id === id)!
    );
    output.push(
      `### ${line(g.title)}`,
      "",
      `- 変更: ${line(g.change)}`,
      `- 影響: ${line(g.impact)}`,
      `- 対応: ${line(g.action)}`,
      `- 確度: ${groupConfidence(sources)} — ${line(g.confidence_note)}`,
      ...sources.flatMap((i) =>
        i.limitations.map((l) => `- 資料の制約: ${line(l)}`)
      ),
      ...sources.map((i) => `- 根拠: <${i.link}>`),
      "",
    );
  }
  return output.join("\n");
}
export function httpURL(s: string): string {
  const u = new URL(s);
  if (!["http:", "https:"].includes(u.protocol) || u.username || u.password) {
    throw new Error("invalid source URL");
  }
  return u.href;
}
export function skippedItem(
  entry: Entry,
  decision: "unavailable" | "manual",
  reason: string,
  limitations: string[] = [],
): SavedItem {
  let link = "";
  try {
    link = httpURL(entry.link);
  } catch {
    limitations = [...limitations, "不正または未取得の URL を記録から除去"];
  }
  return {
    ...entry,
    link,
    decision,
    reason,
    context_complete: false,
    limitations,
    confidence: "uncertain",
    group_id: null,
  };
}
export function usableArticle(
  body: string,
  page: { status?: number; blocked?: boolean } = {},
): boolean {
  return body.trim().length >= 80 &&
    !(typeof page.status === "number" && page.status >= 400) && !page.blocked;
}

export function needsArticlePageCheck(body: string): boolean {
  const firstLine = body.trim().split("\n")[0].replace(/^#{1,6}\s+/, "").trim();
  return /^(?:HTTP\s*(?:403|404)(?:\s+(?:Forbidden|Not Found))?|access denied|page not found|not found|just a moment[.!…]*|attention required!\s*\|\s*cloudflare)$/i
    .test(firstLine) ||
    /cloudflare ray id|checking your browser|verify (?:that )?you are human/i
      .test(body);
}
export function codexArgs(
  cwd: string,
  schema: string,
  output: string,
  prompt: string,
): string[] {
  return [
    "exec",
    "--ignore-user-config",
    "--ephemeral",
    "--skip-git-repo-check",
    "--sandbox",
    "read-only",
    "-C",
    cwd,
    "-m",
    MODEL,
    "-c",
    'model_reasoning_effort="medium"',
    "-c",
    "project_doc_max_bytes=0",
    "-c",
    'web_search="disabled"',
    "--disable",
    "hooks",
    "--disable",
    "memories",
    "--disable",
    "shell_snapshot",
    "--disable",
    "shell_tool",
    "--disable",
    "daemon_auto_start",
    "--output-schema",
    schema,
    "--output-last-message",
    output,
    prompt,
  ];
}

export async function codexEnvironment(
  directory: string,
): Promise<Record<string, string>> {
  const source = Deno.env.get("CODEX_HOME") || `${Deno.env.get("HOME")}/.codex`;
  const target = `${directory}/codex-home`;
  await Deno.mkdir(target, { mode: 0o700 });
  // CODEX_HOME を分けても、認証情報の複製や別ログインは作らない。
  try {
    const auth = await Deno.realPath(`${source}/auth.json`);
    await Deno.symlink(auth, `${target}/auth.json`);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return { CODEX_HOME: target };
}
