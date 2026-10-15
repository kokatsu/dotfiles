import {
  type Entry,
  normalizeFeed,
  rec,
  validateFeed,
} from "./feed-entries.ts";
import {
  bytes,
  clip,
  codexArgs,
  codexEnvironment,
  feedKey,
  hash,
  httpURL,
  type Input,
  limitInput,
  MAX_INPUT,
  MODEL,
  needsArticlePageCheck,
  pending,
  type Receipt,
  render,
  type Result,
  type SavedItem,
  segment,
  skippedItem,
  TARGETS,
  usableArticle,
  validateResult,
} from "./feed-summary.ts";

interface Feed {
  last_seen_id?: string;
  last_summarized_id?: string;
  category?: string;
  type?: string;
  url?: string;
}
interface Opml {
  name: string;
  xmlUrl: string;
}
interface Failure {
  id: string;
  count: number;
  reason: string;
  at: string;
}
interface Collected {
  entry: Entry;
  input?: Input;
  error?: FetchFailure;
}
const scripts = new URL(".", import.meta.url).pathname.replace(/\/$/, "");
const decoder = new TextDecoder();
const encoder = new TextEncoder();

class FetchFailure extends Error {
  constructor(
    message: string,
    readonly systemic = false,
    readonly browserFallback = false,
  ) {
    super(message);
  }
}
async function command(
  executable: string,
  args: string[],
  input?: string,
  timeout = 60_000,
  env: Record<string, string> = {},
) {
  const controller = new AbortController();
  const child = new Deno.Command(executable, {
    args,
    env,
    stdin: input === undefined ? "null" : "piped",
    stdout: "piped",
    stderr: "piped",
    signal: controller.signal,
  }).spawn();
  const timer = setTimeout(() => controller.abort(), timeout);
  let writeError: unknown;
  const writing = (async () => {
    if (input !== undefined) {
      const writer = child.stdin.getWriter();
      try {
        await writer.write(encoder.encode(input));
        await writer.close();
      } catch (error) {
        writeError = error;
      }
    }
  })();
  try {
    const output = await child.output();
    await writing;
    if (controller.signal.aborted) {
      throw new FetchFailure(`${executable}: timeout`, true);
    }
    if (writeError && output.success) throw writeError;
    const stderr = decoder.decode(output.stderr);
    if (!output.success) {
      let diagnostic = stderr;
      if (executable === "agent-browser" && args.includes("--json")) {
        try {
          const error = rec(JSON.parse(decoder.decode(output.stdout)))?.error;
          if (typeof error === "string") diagnostic += `\n${error}`;
        } catch { /* Non-JSON failures still have stderr diagnostics. */ }
      }
      const transport =
        /(?:ERR_(?:NAME_NOT_RESOLVED|NAME_RESOLUTION_FAILED|DNS_[A-Z_]+|CONNECTION_[A-Z_]+|NETWORK_[A-Z_]+|INTERNET_DISCONNECTED|ADDRESS_UNREACHABLE|TIMED_OUT|PROXY_CONNECTION_FAILED|TUNNEL_CONNECTION_FAILED)|EAI_(?:AGAIN|FAIL|NONAME)|ENOTFOUND|ECONN(?:REFUSED|RESET|ABORTED)|ENET(?:UNREACH|DOWN)|EHOST(?:UNREACH|DOWN)|ETIMEDOUT|no such host|resolve host|name resolution|network is unreachable|connection refused|timed? out|connection reset)/i
          .test(diagnostic);
      const service = /(?:HTTP\s*(?:401|429|5\d\d)|rate limit)/i.test(
        diagnostic,
      );
      const forbidden = /HTTP\s*403\b/i.test(diagnostic);
      throw new FetchFailure(
        `${executable}: exit ${output.code}`,
        transport || service || forbidden,
        forbidden && !transport && !service,
      );
    }
    return decoder.decode(output.stdout);
  } catch (error) {
    await writing;
    if (controller.signal.aborted) {
      throw new FetchFailure(`${executable}: timeout`, true);
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}
async function optionalJSON<T>(path: string): Promise<T | null> {
  try {
    return JSON.parse(await Deno.readTextFile(path));
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return null;
    throw error;
  }
}
async function atomic(path: string, data: unknown, text = false) {
  const parent = path.slice(0, path.lastIndexOf("/"));
  await Deno.mkdir(parent, { recursive: true, mode: 0o700 });
  const temp = await Deno.makeTempFile({ dir: parent, prefix: ".feed-" });
  try {
    await Deno.writeTextFile(
      temp,
      text ? String(data) : JSON.stringify(data, null, 2) + "\n",
      { mode: 0o600 },
    );
    await Deno.rename(temp, path);
  } finally {
    await remove(temp);
  }
}
async function remove(path: string) {
  try {
    await Deno.remove(path);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}
function repoFor(feed: Feed): string {
  const match = /^https:\/\/github\.com\/([^/]+\/[^/]+)(?:\/.*)?$/.exec(
    feed.url || "",
  );
  if (!match) throw new Error("cannot derive GitHub repository");
  return match[1];
}
async function api(path: string): Promise<unknown> {
  return JSON.parse(await command("gh", ["api", "-X", "GET", path]));
}
function commitEntry(repo: string, value: unknown): Entry {
  const c = rec(value);
  if (!c || typeof c.sha !== "string" || !c.sha) {
    throw new Error("invalid commit list");
  }
  const info = rec(c.commit);
  return {
    id: c.sha,
    title: String(info?.message || ""),
    date: String(rec(info?.author)?.date || ""),
    link: `https://github.com/${repo}/commit/${encodeURIComponent(c.sha)}`,
  };
}
async function entriesFor(
  feed: Feed,
  opml: Opml,
  boundary: string,
): Promise<Entry[]> {
  if (feed.type === "github") {
    const repo = repoFor(feed);
    const entries: Entry[] = [];
    for (let page = 1; page <= 10; page++) {
      const raw = await api(`repos/${repo}/commits?per_page=100&page=${page}`);
      if (!Array.isArray(raw)) throw new Error("invalid GitHub history");
      entries.push(...raw.map((c) => commitEntry(repo, c)));
      if (entries.some((e) => e.id === boundary)) return entries;
      if (raw.length < 100) break;
    }
    throw new Error(
      "GitHub boundary not found within 1,000 commits; use --reset-progress to select a new boundary",
    );
  }
  if (feed.type !== "feed") throw new Error("unknown feed type");
  const xml = await command("curl", [
    "-sfL",
    "--max-time",
    "30",
    httpURL(opml.xmlUrl),
  ]);
  const json = await command(
    "yq",
    ["-p=xml", "-o=json", "--xml-raw-token=false", "."],
    xml,
  );
  validateFeed(json);
  return normalizeFeed(json);
}
async function commitInput(feed: Feed, entry: Entry): Promise<Input> {
  const repo = repoFor(feed);
  const files: unknown[] = [];
  const limitations: string[] = [];
  let first: Record<string, unknown> | null = null;
  for (let page = 1; page <= 30; page++) {
    const detail = rec(
      await api(
        `repos/${repo}/commits/${
          encodeURIComponent(entry.id)
        }?per_page=100&page=${page}`,
      ),
    );
    if (!detail || !Array.isArray(detail.files)) {
      throw new FetchFailure("invalid commit detail");
    }
    if (page === 1) first = detail;
    files.push(...detail.files);
    if (detail.files.length < 100) break;
    if (page === 30) {
      limitations.push("変更ファイル一覧は取得上限3,000件に到達");
    }
  }
  const mapped = files.map((value) => {
    const f = rec(value);
    if (!f || typeof f.filename !== "string") {
      throw new FetchFailure("invalid change file");
    }
    if (typeof f.patch !== "string") {
      limitations.push(`patch 未取得: ${clip(f.filename, 300)}`);
    }
    return {
      filename: f.filename,
      status: f.status,
      additions: f.additions,
      deletions: f.deletions,
      patch: f.patch ?? null,
    };
  });
  let prs: unknown[] = [];
  try {
    const raw = await api(
      `repos/${repo}/commits/${encodeURIComponent(entry.id)}/pulls?per_page=2`,
    );
    if (!Array.isArray(raw)) throw new Error("invalid PR list");
    prs = raw.slice(0, 1).map((p) => {
      const pr = rec(p);
      return {
        number: pr?.number,
        title: pr?.title,
        body: pr?.body,
        labels: Array.isArray(pr?.labels)
          ? pr.labels.map((l) => rec(l)?.name)
          : [],
      };
    });
    if (raw.length > 1) limitations.push("関連 PR は先頭1件まで");
  } catch (error) {
    if (error instanceof FetchFailure && error.systemic) throw error;
    limitations.push("関連 PR 未取得");
  }
  const info = rec(first?.commit);
  const body = JSON.stringify({
    commit: { message: info?.message, date: rec(info?.author)?.date },
    files: mapped,
    pull_requests: prs,
  });
  if (!info || (!String(info.message || "").trim() && !mapped.length)) {
    throw new FetchFailure("no commit material");
  }
  return limitInput({
    ...entry,
    title: String(info.message || entry.title),
    date: String(rec(info.author)?.date || entry.date),
    body,
    context_complete: limitations.length === 0,
    limitations,
  });
}
async function articleInput(entry: Entry): Promise<Input> {
  let url: string;
  try {
    url = httpURL(entry.link);
  } catch {
    throw new FetchFailure("記事 URL が不正または未取得です");
  }
  let body = "";
  let status: number | undefined;
  try {
    const data = browserData(
      await command("agent-browser", [
        "--session",
        "feed-summarize",
        "--max-output",
        "60000",
        "--json",
        "read",
        url,
      ]),
    );
    if (typeof data.content !== "string" || typeof data.status !== "number") {
      throw new FetchFailure("read の本文または HTTP 状態が不正です", true);
    }
    body = data.content;
    status = data.status;
  } catch (error) {
    if (
      !(error instanceof FetchFailure) ||
      (error.systemic && !error.browserFallback)
    ) {
      throw error;
    }
  }
  if (!usableArticle(body, { status }) || needsArticlePageCheck(body)) {
    await command("agent-browser", [
      "--session",
      "feed-summarize",
      "open",
      url,
    ]);
    const page = rec(
      browserData(
        await command("agent-browser", [
          "--session",
          "feed-summarize",
          "--max-output",
          "60000",
          "--json",
          "eval",
          ARTICLE_PAGE,
        ]),
      ).result,
    );
    if (
      !page || typeof page.body !== "string" ||
      typeof page.blocked !== "boolean"
    ) {
      throw new FetchFailure("ブラウザのページ情報が不正です", true);
    }
    body = page.body;
    status = typeof page.status === "number" ? page.status : undefined;
    if (page.blocked) {
      throw new FetchFailure("ブラウザでアクセス遮断を検出しました", true);
    }
  }
  if (!usableArticle(body, { status })) {
    if (status !== undefined && status >= 400) {
      throw new FetchFailure(
        `記事の HTTP 状態: ${status}`,
        [401, 403, 429].includes(status) || status >= 500,
      );
    }
    throw new FetchFailure("記事本文を確認できません");
  }
  const limitations = [
    "本文取得範囲の完全性、投稿者の公式性、返信の網羅性は未確認",
  ];
  return limitInput({
    ...entry,
    link: url,
    body,
    context_complete: false,
    limitations,
  });
}

function browserData(output: string): Record<string, unknown> {
  const reply = rec(JSON.parse(output));
  const data = rec(reply?.data);
  if (reply?.success !== true || !data) {
    throw new FetchFailure("ブラウザの応答が不正です", true);
  }
  return data;
}

const ARTICLE_PAGE = `(() => {
  const status = performance.getEntriesByType("navigation")[0]?.responseStatus;
  const challenge = document.querySelector("#challenge-form, #challenge-running, #cf-error-details");
  const blocked = !!challenge && /^(?:Just a moment[.!…]*|Attention Required!\\s*\\|\\s*Cloudflare|Access denied)$/i.test(document.title.trim());
  return { body: document.body?.innerText || "", status, blocked };
})()`;

export class Summarizer {
  readonly data: string;
  readonly opml: Opml[] | null;
  readonly prompt: string;
  readonly schema: string;
  readonly promptHash: string;
  constructor(
    readonly statusFile: string,
    opml: Opml[] | null,
    prompt: string,
    schema: string,
    promptHash: string,
  ) {
    this.opml = opml;
    this.prompt = prompt;
    this.schema = schema;
    this.promptHash = promptHash;
    this.data = `${
      Deno.env.get("XDG_DATA_HOME") || `${Deno.env.get("HOME")}/.local/share`
    }/feed-watch`;
  }
  async status(): Promise<Record<string, Feed>> {
    const state = rec(await optionalJSON(this.statusFile));
    const feeds = rec(state?.feeds);
    if (!feeds) throw new Error("invalid feed status");
    return feeds as Record<string, Feed>;
  }
  async advance(name: string, before: string, after: string) {
    await command("bash", [
      "-c",
      'source "$1"; STATUS_FILE="$2"; feed_status_update feed_status_advance "$3" "$4" "$5"',
      "feed-progress",
      `${scripts}/feed-status.sh`,
      this.statusFile,
      name,
      before,
      after,
    ]);
  }
  async dir(name: string) {
    return `${this.data}/decisions/${await feedKey(name)}`;
  }
  source(name: string, feed?: Feed): Opml | undefined {
    if (!feed) return undefined;
    if (this.opml !== null) return this.opml.find((o) => o.name === name);
    if (feed.type === "github") return { name, xmlUrl: "" };
    throw new Error("OPML unavailable for article feed");
  }
  async validateReceipt(r: Receipt, name: string) {
    if (
      !r || r.version !== 1 || !["summary", "reset"].includes(r.kind) ||
      r.feed !== name ||
      typeof r.start !== "string" || typeof r.end !== "string" || !r.end ||
      typeof r.category !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(r.created_at) ||
      !Array.isArray(r.items) || !r.items.length ||
      !Array.isArray(r.warnings) ||
      !r.warnings.every((w) => typeof w === "string") ||
      r.items.at(-1)?.id !== r.end
    ) throw new Error("invalid pending receipt");
    const ids = new Set<string>();
    for (const i of r.items) {
      if (
        !i || typeof i.id !== "string" || !i.id || ids.has(i.id) ||
        typeof i.title !== "string" || typeof i.link !== "string" ||
        typeof i.date !== "string" ||
        typeof i.context_complete !== "boolean" ||
        !Array.isArray(i.limitations) || !i.limitations.every((l) =>
          typeof l === "string"
        ) ||
        !["include", "skip", "unavailable", "manual"].includes(i.decision) ||
        !["official", "reported", "uncertain"].includes(i.confidence) ||
        typeof i.reason !== "string" || !i.reason.trim()
      ) throw new Error("invalid receipt entry");
      if (i.link) httpURL(i.link);
      ids.add(i.id);
    }
    const modeled = r.items.filter((i) =>
      ["include", "skip"].includes(i.decision)
    );
    validateResult(modeled, {
      items: modeled.map(({ id, decision, reason, confidence, group_id }) => ({
        id,
        decision,
        reason,
        confidence,
        group_id,
      })),
      groups: r.groups,
    });
    if (r.kind === "reset" && r.items.some((i) => i.decision !== "manual")) {
      throw new Error("invalid reset receipt");
    }
    if (
      r.batch_id !== await hash([
        r.feed,
        r.start,
        r.kind,
        r.items.map((i) => i.id),
      ])
    ) throw new Error("receipt identity mismatch");
  }
  async finish(r: Receipt) {
    await this.validateReceipt(r, r.feed);
    const feeds = await this.status();
    const f = Object.hasOwn(feeds, r.feed) ? feeds[r.feed] : null;
    if (
      !f || (this.opml !== null && !this.opml.some((o) => o.name === r.feed))
    ) {
      throw new Error("pending feed removed; no progress restored");
    }
    if (![r.start, r.end].includes(f.last_summarized_id || "")) {
      throw new Error("pending progress conflicts with current state");
    }
    const dir = await this.dir(r.feed);
    const stamp = r.created_at.replace(/[-:.]/g, "");
    const path = r.kind === "reset"
      ? `${dir}/resets/${stamp}_${r.batch_id}.json`
      : `${dir}/${r.batch_id}.json`;
    await atomic(path, r);
    const text = render(r);
    if (text) {
      await atomic(
        `${this.data}/summaries/${segment(r.category)}/${stamp}_${await feedKey(
          r.feed,
        )}_${r.batch_id}.md`,
        text,
        true,
      );
    }
    await this.advance(r.feed, r.start, r.end);
    await remove(`${dir}/pending.json`);
  }
  async recover(name: string) {
    const r = await optionalJSON<Receipt>(
      `${await this.dir(name)}/pending.json`,
    );
    if (r) {
      await this.validateReceipt(r, name);
      await this.finish(r);
    }
  }
  async receipt(
    name: string,
    feed: Feed,
    start: string,
    items: SavedItem[],
    result: Result,
    warnings: string[],
    kind: "summary" | "reset" = "summary",
  ): Promise<Receipt> {
    return {
      version: 1,
      kind,
      feed: name,
      category: feed.category || "Uncategorized",
      start,
      end: items.at(-1)!.id,
      batch_id: await hash([name, start, kind, items.map((i) => i.id)]),
      created_at: new Date().toISOString(),
      prompt_hash: this.promptHash,
      model: MODEL,
      items,
      groups: result.groups,
      warnings,
    };
  }
  async save(r: Receipt) {
    await this.validateReceipt(r, r.feed);
    await atomic(`${await this.dir(r.feed)}/pending.json`, r);
    await this.finish(r);
  }
  async model(name: string, items: Input[]): Promise<Result> {
    if (!items.length) return { items: [], groups: [] };
    const cwd = await Deno.makeTempDir({ prefix: "feed-summary-" });
    try {
      const schema = `${cwd}/schema.json`;
      const output = `${cwd}/result.json`;
      await Deno.writeTextFile(schema, this.schema);
      await command(
        "codex",
        codexArgs(cwd, schema, output, this.prompt),
        JSON.stringify({ feed: name, items }),
        180_000,
        await codexEnvironment(cwd),
      );
      return validateResult(items, JSON.parse(await Deno.readTextFile(output)));
    } finally {
      await Deno.remove(cwd, { recursive: true });
    }
  }
  inputSize(name: string, items: Input[]) {
    return bytes(this.prompt) + bytes(this.schema) +
      bytes(JSON.stringify({ feed: name, items }));
  }
  async summarize(name: string) {
    await this.recover(name);
    const feeds = await this.status();
    const feed = feeds[name];
    const opml = this.source(name, feed);
    if (!feed || !opml || !feed.last_seen_id) return;
    let last = feed.last_summarized_id || "";
    if (!last) {
      await this.advance(name, "", feed.last_seen_id);
      return;
    }
    if (last === feed.last_seen_id) return;
    const entries = await entriesFor(feed, opml, last);
    const selection = pending(entries, last, feed.type === "github");
    let warnings = selection.warnings;
    if (!entries.length) {
      console.error(`${name}: empty feed; progress unchanged`);
      return;
    }
    const failurePath = `${await this.dir(name)}/failures.json`;
    const failures = await optionalJSON<Failure[]>(failurePath) || [];
    if (
      !Array.isArray(failures) ||
      failures.some((f) =>
        !f || typeof f.id !== "string" || !Number.isInteger(f.count) ||
        f.count < 1
      )
    ) throw new Error("invalid failure record");
    const alive = new Set(selection.items.map((i) => i.id));
    const counts = new Map(
      failures.filter((f) => alive.has(f.id)).map((f) => [f.id, f]),
    );
    let anySuccess = false;
    for (let offset = 0; offset < selection.items.length;) {
      const candidates = selection.items.slice(offset, offset + 20);
      const collected: Collected[] = [];
      for (const entry of candidates) {
        try {
          const input = feed.type === "github"
            ? await commitInput(feed, entry)
            : await articleInput(entry);
          anySuccess = true;
          counts.delete(entry.id);
          collected.push({ entry, input });
        } catch (error) {
          if (!(error instanceof FetchFailure) || error.systemic) throw error;
          collected.push({ entry, error });
        }
      }
      const ready: (Input | SavedItem)[] = [];
      let blocked = false;
      for (const c of collected) {
        if (c.input) {
          if (!blocked) ready.push(c.input);
          continue;
        }
        let f = counts.get(c.entry.id);
        if (anySuccess) {
          f = {
            id: c.entry.id,
            count: (f?.count || 0) + 1,
            reason: c.error!.message,
            at: new Date().toISOString(),
          };
          counts.set(c.entry.id, f);
        }
        if ((f?.count || 0) < 3) blocked = true;
        if (!blocked) {
          ready.push(
            skippedItem(c.entry, "unavailable", "取得不能（原因未確定）", [
              c.error!.message,
            ]),
          );
        }
      }
      await atomic(failurePath, [...counts.values()]);
      let consumed = 0;
      while (consumed < ready.length) {
        const chunk: (Input | SavedItem)[] = [];
        const inputs: Input[] = [];
        for (const candidate of ready.slice(consumed)) {
          const prospective = "body" in candidate
            ? [...inputs, candidate]
            : inputs;
          if (this.inputSize(name, prospective) > MAX_INPUT) {
            if (chunk.length) break;
            if (!("body" in candidate)) {
              throw new Error("prompt exceeds input limit");
            }
            const overhead = this.inputSize(name, [{ ...candidate, body: "" }]);
            const budget = Math.max(
              0,
              Math.floor((MAX_INPUT - overhead - 1024) / 6),
            );
            candidate.body = clip(candidate.body, budget);
            candidate.context_complete = false;
            candidate.limitations.push("バッチ入力上限で資料を省略");
            if (
              !candidate.body || this.inputSize(name, [candidate]) > MAX_INPUT
            ) throw new Error("single entry exceeds input limit");
          }
          chunk.push(candidate);
          if ("body" in candidate) inputs.push(candidate);
        }
        const result = await this.model(name, inputs);
        const saved = chunk.map((item): SavedItem => {
          if (!("body" in item)) return item;
          const { body: _body, ...metadata } = item;
          return {
            ...metadata,
            ...result.items.find((d) => d.id === item.id)!,
          };
        });
        const alerts = [
          ...warnings,
          ...saved.filter((i) => i.decision === "unavailable").map((i) =>
            `${i.id}: ${i.reason}。${i.link}`
          ),
        ];
        await this.save(
          await this.receipt(name, feed, last, saved, result, alerts),
        );
        last = saved.at(-1)!.id;
        warnings = [];
        consumed += chunk.length;
      }
      if (blocked) {
        throw new Error(
          "article material unavailable; retry later or use --reset-progress",
        );
      }
      offset += candidates.length;
    }
  }
  async reset(name: string, to: string, reason: string) {
    if (!TARGETS.includes(name)) throw new Error("unknown summary feed");
    if (await optionalJSON(`${await this.dir(name)}/pending.json`)) {
      throw new Error("pending record exists; run summaries to recover first");
    }
    const feed = (await this.status())[name];
    const opml = this.source(name, feed);
    if (!feed || !opml) throw new Error("feed is not monitored");
    const entries = await entriesFor(feed, opml, to);
    const index = entries.findIndex((e) => e.id === to);
    if (index < 0) throw new Error("reset ID not in fetched history");
    const start = feed.last_summarized_id || "";
    const before = entries.findIndex((e) => e.id === start);
    if (to === start || (before >= 0 && index >= before)) {
      throw new Error("reset must advance progress");
    }
    const skipped = entries.slice(index, before < 0 ? undefined : before)
      .reverse();
    const warnings = [
      `手動で未処理範囲を飛ばしました: (${
        start || "未設定"
      }, ${to}]。理由: ${reason}。自動回収しません。`,
      ...(before < 0
        ? [
          "旧境界が取得範囲にないため、全件数と全範囲は不明です。以下は確認できた ID のみです。",
        ]
        : []),
      `確認できた ID: ${skipped.map((e) => e.id).join(", ")}`,
    ];
    const saved = skipped.map((e) => skippedItem(e, "manual", reason));
    await this.save(
      await this.receipt(
        name,
        feed,
        start,
        saved,
        { items: [], groups: [] },
        warnings,
        "reset",
      ),
    );
    for (const w of warnings) console.log(w);
  }
}
async function main(): Promise<number> {
  const [status, opmlJSON, ...args] = Deno.args;
  const prompt = await Deno.readTextFile(`${scripts}/feed-summarize-prompt.md`);
  const schema = await Deno.readTextFile(
    `${scripts}/feed-summarize.schema.json`,
  );
  const opml = JSON.parse(opmlJSON) as Opml[] | null;
  const engine = new Summarizer(
    status,
    opml,
    prompt,
    schema,
    await hash([prompt, schema]),
  );
  if (args[0] === "--reset-progress") {
    if (
      args.length !== 6 || args[2] !== "--to" || args[4] !== "--reason" ||
      !args[3] || !args[5].trim()
    ) {
      throw new Error(
        "usage: feed-summarize --reset-progress <feed> --to <id> --reason <reason>",
      );
    }
    await engine.reset(args[1], args[3], args[5]);
    return 0;
  }
  if (args.length > 1 || args[0]?.startsWith("-")) {
    throw new Error("usage: feed-summarize [category]");
  }
  let code = 0;
  for (const name of TARGETS) {
    const f = (await engine.status())[name];
    if (!f || (args[0] && f.category !== args[0])) continue;
    try {
      await engine.summarize(name);
    } catch (error) {
      console.error(
        `${name}: ${error instanceof Error ? error.message : "summary failed"}`,
      );
      code = 1;
    }
  }
  return code;
}
if (import.meta.main) {
  try {
    Deno.exit(await main());
  } catch (error) {
    console.error(
      error instanceof Error ? error.message : "feed summary failed",
    );
    Deno.exit(1);
  }
}
