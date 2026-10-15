import {
  bytes,
  clip,
  codexArgs,
  groupConfidence,
  type Input,
  limitInput,
  MAX_BODY,
  pending,
  type Receipt,
  render,
  TARGETS,
  usableArticle,
  validateResult,
} from "./feed-summary.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
function rejects(fn: () => unknown) {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error("expected rejection");
}
const input: Input = {
  id: "a",
  title: "Change",
  link: "https://example.com/a",
  date: "2026-10-15",
  body: "body",
  context_complete: true,
  limitations: [],
};
function response() {
  return {
    items: [{
      id: "a",
      decision: "include",
      reason: "API change",
      confidence: "official",
      group_id: "g",
    }],
    groups: [{
      group_id: "g",
      item_ids: ["a"],
      title: "Change",
      change: "change",
      impact: "impact",
      action: "action",
      confidence_note: "note",
    }],
  };
}
Deno.test("response validation rejects missing, duplicate, foreign and misgrouped IDs", () => {
  validateResult([input], response());
  const cases = [
    { ...response(), items: [] },
    { ...response(), items: [...response().items, ...response().items] },
    { ...response(), items: [{ ...response().items[0], id: "unknown" }] },
    { ...response(), groups: [] },
    {
      ...response(),
      groups: [{ ...response().groups[0], item_ids: ["unknown"] }],
    },
    {
      ...response(),
      groups: [{ ...response().groups[0], item_ids: ["a", "a"] }],
    },
    { ...response(), items: [{ ...response().items[0], decision: "skip" }] },
    { ...response(), items: [{ ...response().items[0], reason: " " }] },
    {
      ...response(),
      items: [{ ...response().items[0], context_complete: true }],
    },
  ];
  for (const c of cases) rejects(() => validateResult([input], c));
});
Deno.test("UTF-8 bounds omit partial characters and mark omitted context", () => {
  equal(clip("あいう", 7), "あい");
  const limited = limitInput({ ...input, body: "あ".repeat(MAX_BODY) });
  if (bytes(limited.body) > MAX_BODY || limited.body.includes("�")) {
    throw new Error("invalid truncation");
  }
  equal(limited.context_complete, false);
  rejects(() => limitInput({ ...input, id: "x".repeat(33 * 1024) }));
});
Deno.test("RSS missing boundary keeps available entries; GitHub refuses", () => {
  const rows = [{ ...input, id: "b" }, input];
  equal(pending(rows, "old", false).items.map((i) => i.id), ["a", "b"]);
  equal(pending(rows, "old", false).warnings.length, 1);
  rejects(() => pending(rows, "old", true));
  rejects(() => pending([input, input], "old", false));
  equal(pending(rows, "a", false).items.map((i) => i.id), ["b"]);
});
Deno.test("entry IDs are validated only in the unprocessed range", () => {
  const row = (id: string) => ({ ...input, id });
  for (const github of [false, true]) {
    equal(
      pending(
        ["new", "old", "new", "", "older", "older"].map(row),
        "old",
        github,
      )
        .items.map((i) => i.id),
      ["new"],
    );
    rejects(() => pending(["new", "new", "old"].map(row), "old", github));
    rejects(() => pending(["new", "", "old"].map(row), "old", github));
  }
});
Deno.test("group certainty never increases and partial sources remain visible", () => {
  const result = validateResult([input], response());
  const saved = {
    ...input,
    ...result.items[0],
    confidence: "reported" as const,
    limitations: ["本文は一部のみ"],
  };
  equal(
    groupConfidence([saved, { ...saved, confidence: "official" }]),
    "reported",
  );
  equal(
    groupConfidence([saved, { ...saved, confidence: "uncertain" }]),
    "uncertain",
  );
  const receipt = {
    feed: "Demo",
    kind: "summary",
    created_at: "now",
    items: [saved],
    groups: result.groups,
    warnings: [],
  } as unknown as Receipt;
  const text = render(receipt)!;
  if (
    !text.includes("reported") || !text.includes(input.link) ||
    !text.includes("本文は一部のみ")
  ) throw new Error("missing provenance");
  equal(render({ ...receipt, groups: [] }), null);
  if (
    !render({ ...receipt, groups: [], warnings: ["履歴欠落"] })?.includes(
      "履歴欠落",
    )
  ) throw new Error("missing warning");
});
Deno.test("summary targets and Codex isolation options", () => {
  equal(TARGETS.includes("Claude Release Notes"), false);
  equal(TARGETS.includes("Social Media Today"), true);
  const args = codexArgs("/tmp/work", "/tmp/schema", "/tmp/out", "prompt");
  for (
    const expected of [
      "--ignore-user-config",
      "project_doc_max_bytes=0",
      "hooks",
      "memories",
      "shell_tool",
      "read-only",
    ]
  ) if (!args.includes(expected)) throw new Error(expected);
  equal(usableArticle("Access denied"), false);
  equal(usableArticle("x".repeat(100) + " Cloudflare Ray ID"), true);
  equal(usableArticle("x".repeat(100), { status: 404 }), false);
  equal(usableArticle("x".repeat(100), { status: 200, blocked: true }), false);
});

const root = new URL("..", import.meta.url).pathname.replace(/\/$/, "");
const originalPath = Deno.env.get("PATH") || "";
async function fixture(run: (f: Fixture) => Promise<void>) {
  const dir = await Deno.makeTempDir({ prefix: "feed-summary-test-" });
  try {
    const f = new Fixture(dir);
    await f.init();
    await run(f);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}
class Fixture {
  name = "Social Media Today";
  constructor(readonly dir: string) {}
  async write(path: string, text: string) {
    await Deno.writeTextFile(`${this.dir}/${path}`, text);
  }
  async json(path: string, value: unknown) {
    await this.write(path, JSON.stringify(value));
  }
  async read(path: string) {
    return JSON.parse(await Deno.readTextFile(`${this.dir}/${path}`));
  }
  async init() {
    for (const name of ["bin", "opml", "state", "data"]) {
      await Deno.mkdir(`${this.dir}/${name}`);
    }
    await this.write(
      "opml/feeds.opml",
      `<opml><body><outline text="Articles"><outline text="${this.name}" xmlUrl="https://example.com/feed"/></outline></body></opml>`,
    );
    await this.state("old", "c");
    await this.feed(["c", "b", "a", "old"]);
    await this.write(
      "bin/curl",
      '#!/usr/bin/env bash\ncat "$FEED_TEST_DIR/feed.xml"\n',
    );
    await this.write(
      "bin/agent-browser",
      `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *close*) exit 0 ;;
  *'read '*|*'open '*) for url; do :; done; basename "$url" >"$FEED_TEST_DIR/current" ;;
esac
if [[ "$*" == *'open '* ]]; then exit 0; fi
id=$(cat "$FEED_TEST_DIR/current")
status=200
body="Article $id has a concrete change in API access requirements and enough text to represent normal article content."
if [[ -f "$FEED_TEST_DIR/fail-$id" ]]; then status=404; body='Access denied'; fi
if [[ "$*" == *'read '* ]]; then
  jq -n --arg content "$body" --argjson status "$status" '{success:true,data:{content:$content,status:$status}}'
else
  jq -n --arg body "$body" --argjson status "$status" '{success:true,data:{result:{body:$body,status:$status,blocked:false}}}'
fi
`,
    );
    await this.write(
      "bin/codex",
      `#!/usr/bin/env bash
set -euo pipefail
[[ ! -e /proc/$$/fd/8 && ! -e /proc/$$/fd/9 ]] || exit 99
output=
while (($#)); do
  if [[ "$1" == --output-last-message ]]; then output=$2; shift; fi
  shift
done
cat >"$FEED_TEST_DIR/model-input.json"
printf 'call\\n' >>"$FEED_TEST_DIR/model-calls"
if [[ -f "$FEED_TEST_DIR/model-fail" ]]; then exit 1; fi
if [[ -f "$FEED_TEST_DIR/invalid" ]]; then printf '{}' >"$output"; exit 0; fi
if [[ -f "$FEED_TEST_DIR/skip" ]]; then
  jq '{items:[.items[]|{id,decision:"skip",reason:"irrelevant",confidence:"reported",group_id:null}],groups:[]}' "$FEED_TEST_DIR/model-input.json" >"$output"
else
  jq '{items:[.items[]|{id,decision:"include",reason:"API change",confidence:"reported",group_id:.id}],groups:[.items[]|{group_id:.id,item_ids:[.id],title:.title,change:"change",impact:"impact",action:"資料に記載なし",confidence_note:"report"}]}' "$FEED_TEST_DIR/model-input.json" >"$output"
fi
`,
    );
    for (const cmd of ["curl", "agent-browser", "codex"]) {
      await Deno.chmod(`${this.dir}/bin/${cmd}`, 0o755);
    }
  }
  async github(ids: string[]) {
    this.name = "Recent Commits to docs:main";
    await this.write(
      "opml/feeds.opml",
      `<opml><body><outline text="Articles"><outline text="${this.name}" xmlUrl="https://github.com/example/docs/commits.atom"/></outline></body></opml>`,
    );
    await this.state("old", ids[0]);
    const state = await this.read("state/status.json");
    state.feeds[this.name].type = "github";
    state.feeds[this.name].url = "https://github.com/example/docs";
    await this.json("state/status.json", state);
    for (let start = 0; start < ids.length; start += 100) {
      await this.json(
        `history-${start / 100 + 1}.json`,
        ids.slice(start, start + 100).map((id) => ({
          sha: id,
          commit: { message: id, author: { date: "2026-10-15" } },
        })),
      );
    }
    await this.write(
      "bin/gh",
      `#!/usr/bin/env bash
set -euo pipefail
for endpoint; do :; done
printf '%s\\n' "$endpoint" >>"$FEED_TEST_DIR/gh-calls"
case "$endpoint" in
  *'/pulls?'*)
    if [[ -f "$FEED_TEST_DIR/prs.json" ]]; then cat "$FEED_TEST_DIR/prs.json"; else printf '[]'; fi ;;
  *'/commits?'*) page=$(printf '%s' "$endpoint" | sed 's/.*page=//'); cat "$FEED_TEST_DIR/history-$page.json" ;;
  *)
    if [[ -f "$FEED_TEST_DIR/detail-pages" ]]; then
      case "$endpoint" in
        *'page=1') cat "$FEED_TEST_DIR/detail-1.json" ;;
        *'page=2') cat "$FEED_TEST_DIR/detail-2.json" ;;
        *) exit 1 ;;
      esac
    else
      printf '%s' '{"commit":{"message":"API authentication requirement changed","author":{"date":"2026-10-15"}},"files":[{"filename":"auth.md","patch":"- old\\n+ new"}]}'
    fi ;;
esac
`,
    );
    await Deno.chmod(`${this.dir}/bin/gh`, 0o755);
  }
  async state(last: string, seen: string) {
    await this.json("state/status.json", {
      extra: "keep",
      feeds: {
        [this.name]: {
          type: "feed",
          category: "Articles",
          last_summarized_id: last,
          last_seen_id: seen,
          unread_count: 76,
        },
      },
    });
  }
  async feed(ids: string[]) {
    await this.write(
      "feed.xml",
      `<rss><channel>${
        ids.map((id) =>
          `<item><guid>${id}</guid><title>${id}</title><link>https://example.com/${id}</link></item>`
        ).join("")
      }</channel></rss>`,
    );
  }
  async run(args: string[] = []) {
    const out = await new Deno.Command("bash", {
      args: [`${root}/bin/feed-summarize`, ...args],
      env: {
        PATH: `${this.dir}/bin:${originalPath}`,
        FEED_TEST_DIR: this.dir,
        FEED_WATCH_STATUS_DIR: `${this.dir}/state`,
        FEED_WATCH_OPML_DIR: `${this.dir}/opml`,
        XDG_DATA_HOME: `${this.dir}/data`,
      },
      stdout: "piped",
      stderr: "piped",
    }).output();
    return {
      code: out.code,
      stdout: new TextDecoder().decode(out.stdout),
      stderr: new TextDecoder().decode(out.stderr),
    };
  }
  async progress() {
    const state = await this.read("state/status.json");
    equal(state.extra, "keep");
    equal(state.feeds[this.name].unread_count, 76);
    return state.feeds[this.name].last_summarized_id;
  }
  async files(path: string, suffix: string): Promise<string[]> {
    const all: string[] = [];
    try {
      for await (const e of Deno.readDir(`${this.dir}/${path}`)) {
        if (e.isDirectory) {
          all.push(...await this.files(`${path}/${e.name}`, suffix));
        } else if (e.name.endsWith(suffix)) all.push(`${path}/${e.name}`);
      }
    } catch (e) {
      if (!(e instanceof Deno.errors.NotFound)) throw e;
    }
    return all;
  }
  async calls() {
    try {
      return (await Deno.readTextFile(`${this.dir}/model-calls`)).trim().split(
        "\n",
      ).length;
    } catch (e) {
      if (e instanceof Deno.errors.NotFound) return 0;
      throw e;
    }
  }
}
function integration(name: string, fn: (f: Fixture) => Promise<void>) {
  Deno.test({ name, ignore: Deno.build.os !== "linux", fn: () => fixture(fn) });
}
integration("unclosed feed elements never advance progress", async (f) => {
  const xml =
    "<rss><channel><item><guid>new</guid><link>https://example.com/new</link></item>";
  for (const body of [xml, `${xml}</channel></rss><unfinished>`]) {
    await f.write("feed.xml", body);
    const result = await f.run();
    equal(result.code, 1);
    equal(await f.progress(), "old");
    equal(await f.calls(), 0);
  }
});
integration("invalid processed IDs do not prevent summarization", async (f) => {
  await f.feed(["new", "old", "new", "older", "older"]);
  await f.write(
    "feed.xml",
    (await Deno.readTextFile(`${f.dir}/feed.xml`)).replace(
      "</channel>",
      "<item><title>No identity</title></item></channel>",
    ),
  );
  await f.state("old", "new");
  equal((await f.run()).code, 0);
  equal(await f.progress(), "new");
  equal((await f.read("model-input.json")).items.map((i: Input) => i.id), [
    "new",
  ]);
});
integration("invalid unprocessed IDs stop without advancing", async (f) => {
  for (
    const entries of [
      "<item><guid>new</guid></item><item><guid>new</guid></item>",
      "<item><guid>new</guid></item><item><title>No identity</title></item>",
    ]
  ) {
    await f.write(
      "feed.xml",
      `<rss><channel>${entries}<item><guid>old</guid></item></channel></rss>`,
    );
    const result = await f.run();
    equal(result.code, 1);
    equal(result.stderr.includes("empty or duplicate entry ID"), true);
    equal(await f.progress(), "old");
    equal(await f.calls(), 0);
  }
});
integration(
  "all skipped advances without Markdown; RSS gaps still create warnings",
  async (f) => {
    await f.write("skip", "");
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    equal((await f.files("data/feed-watch/summaries", ".md")).length, 0);
    await f.state("missing", "c");
    equal((await f.run()).code, 0);
    equal((await f.files("data/feed-watch/summaries", ".md")).length, 1);
  },
);
integration(
  "failure stops at the prefix and counts only with a successful peer",
  async (f) => {
    await f.write("fail-b", "");
    equal((await f.run()).code, 1);
    equal(await f.progress(), "a");
    equal((await f.run()).code, 1);
    equal(await f.progress(), "a");
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    const receipts = await f.files("data/feed-watch/decisions", ".json");
    const records = await Promise.all(receipts.map((p) => f.read(p)));
    if (
      !records.some((r) =>
        Array.isArray(r.items) &&
        r.items.some((i: { decision: string }) => i.decision === "unavailable")
      )
    ) throw new Error("missing unavailable decision");
  },
);
integration(
  "all failed and singleton failed never consume retry budget",
  async (f) => {
    for (const id of ["a", "b", "c"]) await f.write(`fail-${id}`, "");
    for (let i = 0; i < 3; i++) equal((await f.run()).code, 1);
    equal(await f.progress(), "old");
    const ledger =
      (await f.files("data/feed-watch/decisions", "failures.json"))[0];
    equal(await f.read(ledger), []);
    await f.feed(["a", "old"]);
    await f.state("old", "a");
    equal((await f.run()).code, 1);
    equal(await f.progress(), "old");
    equal(await f.calls(), 0);
  },
);
integration(
  "pending receipt recovers without calling Codex again",
  async (f) => {
    await Deno.mkdir(`${f.dir}/data/feed-watch/summaries`, { recursive: true });
    await f.write("data/feed-watch/summaries/Articles", "block publication");
    equal((await f.run()).code, 1);
    equal(await f.progress(), "old");
    equal(await f.calls(), 1);
    const pending = await f.files("data/feed-watch/decisions", "pending.json");
    equal(pending.length, 1);
    await Deno.remove(`${f.dir}/data/feed-watch/summaries/Articles`);
    await f.write("model-fail", "");
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    equal(await f.calls(), 1);
    equal(
      (await f.files("data/feed-watch/decisions", "pending.json")).length,
      0,
    );
    equal((await f.files("data/feed-watch/summaries", ".md")).length, 1);
  },
);
integration("invalid model output never advances", async (f) => {
  await f.write("invalid", "");
  equal((await f.run()).code, 1);
  equal(await f.progress(), "old");
  equal((await f.files("data/feed-watch/decisions", "pending.json")).length, 0);
});
integration(
  "RSS reset validates ID and records the whole skipped prefix",
  async (f) => {
    equal(
      (await f.run([
        "--reset-progress",
        f.name,
        "--to",
        "unknown",
        "--reason",
        "test",
      ])).code,
      1,
    );
    equal(await f.progress(), "old");
    const out = await f.run([
      "--reset-progress",
      f.name,
      "--to",
      "b",
      "--reason",
      "blocked",
    ]);
    equal(out.code, 0);
    equal(await f.progress(), "b");
    equal(await f.calls(), 0);
    if (!out.stdout.includes("a, b")) throw new Error(out.stdout);
    const files = await f.files("data/feed-watch/decisions", ".json");
    const reset = (await Promise.all(files.map((p) => f.read(p)))).find((r) =>
      r.kind === "reset"
    );
    equal(reset.items.map((i: { id: string }) => i.id), ["a", "b"]);
  },
);
integration(
  "more than twenty entries are processed in ordered batches",
  async (f) => {
    const ids = Array.from({ length: 25 }, (_, i) => `entry-${i + 1}`)
      .reverse();
    await f.feed([...ids, "old"]);
    await f.state("old", ids[0]);
    equal((await f.run()).code, 0);
    equal(await f.progress(), ids[0]);
    equal(await f.calls(), 2);
  },
);
integration(
  "first run initializes Social Media Today without backlog",
  async (f) => {
    await f.state("", "c");
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    equal(await f.calls(), 0);
  },
);

integration("GitHub history finds an old boundary on page four", async (f) => {
  const ids = [
    ...Array.from({ length: 318 }, (_, i) => `sha-${318 - i}`),
    "old",
  ];
  await f.github(ids);
  equal((await f.run()).code, 0);
  equal(await f.progress(), ids[0]);
  equal(await f.calls(), 16);
});
for (const count of [0, 1, 2]) {
  integration(
    `GitHub PR material completeness with ${count} PRs`,
    async (f) => {
      await f.github(["new", "old"]);
      await f.json(
        "prs.json",
        Array.from({ length: count }, (_, i) => ({
          number: i + 1,
          title: `PR ${i + 1}`,
          body: `Change ${i + 1}`,
        })),
      );
      equal((await f.run()).code, 0);
      const item = (await f.read("model-input.json")).items[0];
      equal(item.context_complete, count < 2);
      equal(item.limitations, count < 2 ? [] : ["関連 PR は先頭1件まで"]);
      equal(JSON.parse(item.body).pull_requests.length, Math.min(count, 1));
      const calls = await Deno.readTextFile(`${f.dir}/gh-calls`);
      equal(calls.includes("/pulls?per_page=2"), true);
    },
  );
}
integration(
  "GitHub file list is paginated without duplicating commit info",
  async (f) => {
    await f.github(["new", "old"]);
    await f.write("detail-pages", "");
    const commit = { message: "auth changed", author: { date: "2026-10-15" } };
    await f.json("detail-1.json", {
      commit,
      files: Array.from(
        { length: 100 },
        (_, i) => ({ filename: `doc-${i}.md`, patch: "-old\n+new" }),
      ),
    });
    await f.json("detail-2.json", {
      commit,
      files: [{ filename: "page-two.md", patch: "+new" }],
    });
    equal((await f.run()).code, 0);
    equal(await f.progress(), "new");
    const input = await f.read("model-input.json");
    const body = JSON.parse(input.items[0].body);
    equal(body.files.length, 101);
    equal(body.files.at(-1).filename, "page-two.md");
  },
);
integration(
  "GitHub refuses a missing boundary at the fixed history limit",
  async (f) => {
    const ids = Array.from({ length: 1000 }, (_, i) => `sha-${1000 - i}`);
    await f.github(ids);
    equal((await f.run()).code, 1);
    equal(await f.progress(), "old");
    equal(await f.calls(), 0);
  },
);
integration("reset refuses a pending publication", async (f) => {
  await Deno.mkdir(`${f.dir}/data/feed-watch/summaries`, { recursive: true });
  await f.write("data/feed-watch/summaries/Articles", "blocked");
  equal((await f.run()).code, 1);
  equal(
    (await f.run([
      "--reset-progress",
      f.name,
      "--to",
      "c",
      "--reason",
      "blocked",
    ])).code,
    1,
  );
  equal(await f.progress(), "old");
});
integration("large articles split by serialized input size", async (f) => {
  await f.write(
    "bin/agent-browser",
    `#!/usr/bin/env bash
case "$*" in *close*) exit 0 ;; esac
body=$(head -c 48000 /dev/zero | tr '\\0' x)
jq -n --arg content "$body" '{success:true,data:{content:$content,status:200}}'
`,
  );
  equal((await f.run()).code, 0);
  equal(await f.progress(), "c");
  equal(await f.calls(), 2);
});

integration(
  "invalid article URLs can be recorded as unavailable",
  async (f) => {
    await f.feed(["c", "b", "a", "old"]);
    const xml = await Deno.readTextFile(`${f.dir}/feed.xml`);
    await f.write(
      "feed.xml",
      xml.replace("https://example.com/b", "not-a-url"),
    );
    equal((await f.run()).code, 1);
    equal(await f.progress(), "a");
    equal((await f.run()).code, 1);
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    const records = await Promise.all(
      (await f.files("data/feed-watch/decisions", ".json")).map((p) =>
        f.read(p)
      ),
    );
    const item = records.flatMap((r) => r.items || []).find((i) =>
      i.id === "b"
    );
    equal(item.decision, "unavailable");
    equal(item.link, "");
  },
);

integration(
  "RSS reset removes invalid URLs in the entire skipped range",
  async (f) => {
    const xml = await Deno.readTextFile(`${f.dir}/feed.xml`);
    await f.write(
      "feed.xml",
      xml.replace("https://example.com/a", "javascript:alert(1)").replace(
        "https://example.com/b",
        "not-a-url",
      ),
    );
    const out = await f.run([
      "--reset-progress",
      f.name,
      "--to",
      "b",
      "--reason",
      "invalid URLs",
    ]);
    equal(out.code, 0);
    equal(await f.progress(), "b");
    const paths = await f.files("data/feed-watch/decisions", ".json");
    const receipt = (await Promise.all(paths.map((p) => f.read(p)))).find((r) =>
      r.kind === "reset"
    );
    equal(
      receipt.items.map((i: { id: string; link: string }) => [i.id, i.link]),
      [["a", ""], ["b", ""]],
    );
  },
);

integration("prefixed Atom and RSS roots can be summarized", async (f) => {
  for (
    const xml of [
      '<atom:feed xmlns:atom="http://www.w3.org/2005/Atom"><atom:entry><atom:id>a</atom:id><atom:title>a</atom:title><atom:link href="https://example.com/a"/></atom:entry><atom:entry><atom:id>old</atom:id></atom:entry></atom:feed>',
      '<r:rss xmlns:r="urn:feed"><r:channel><r:item><r:guid>a</r:guid><r:title>a</r:title><r:link>https://example.com/a</r:link></r:item><r:item><r:guid>old</r:guid></r:item></r:channel></r:rss>',
    ]
  ) {
    await f.state("old", "a");
    await f.write("feed.xml", xml);
    const out = await f.run();
    equal(out.code, 0);
    equal(await f.progress(), "a");
  }
});

for (
  const error of [
    "net::ERR_NAME_NOT_RESOLVED",
    "lookup example.com: no such host",
    "getaddrinfo EAI_AGAIN example.com",
    "net::ERR_CONNECTION_REFUSED",
    "Could not resolve host: example.com",
  ]
) {
  integration(`transport failures preserve retries: ${error}`, async (f) => {
    const browser = await Deno.readTextFile(`${f.dir}/bin/agent-browser`);
    await f.write("network-error", error);
    await f.write(
      "bin/agent-browser",
      `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$FEED_TEST_DIR/browser-calls"
case "$*" in
  *close*) exit 0 ;;
  *'read '*|*'open '*) for url; do :; done; basename "$url" >"$FEED_TEST_DIR/current" ;;
esac
id=$(cat "$FEED_TEST_DIR/current")
if [[ "$id" == b && "$*" == *'read '* ]]; then
  cat "$FEED_TEST_DIR/network-error" >&2
  exit 1
fi
if [[ "$*" == *'open '* ]]; then exit 0; fi
body='A normal article describes an API change and has enough text to distinguish successful content retrieval from an error.'
if [[ "$*" == *'read '* ]]; then
  jq -n --arg content "$body" '{success:true,data:{content:$content,status:200}}'
else
  jq -n '{success:true,data:{result:{body:"Access denied",status:404,blocked:false}}}'
fi
`,
    );
    for (let run = 0; run < 3; run++) {
      equal((await f.run()).code, 1);
      equal(await f.progress(), "old");
    }
    equal(await f.calls(), 0);
    equal(
      (await f.files("data/feed-watch/decisions", "failures.json")).length,
      0,
    );
    const calls = await Deno.readTextFile(`${f.dir}/browser-calls`);
    if (calls.includes("open ")) {
      throw new Error("network error fell back to browser");
    }
    await f.write("bin/agent-browser", browser);
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
  });
}

integration(
  "read HTTP 403 still uses a successful browser fallback",
  async (f) => {
    await f.write(
      "bin/agent-browser",
      `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >>"$FEED_TEST_DIR/browser-calls"
case "$*" in
  *close*) exit 0 ;;
  *'read '*) printf 'HTTP 403 Forbidden' >&2; exit 1 ;;
  *'open '*) exit 0 ;;
esac
jq -n '{success:true,data:{result:{body:"A normal article from the browser contains an API requirement change with enough text to serve as usable content.",status:200,blocked:false}}}'
`,
    );
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    const calls = await Deno.readTextFile(`${f.dir}/browser-calls`);
    if (!calls.includes("open ")) throw new Error("missing HTTP 403 fallback");
  },
);

integration(
  "browser fallback DNS failure never consumes retries",
  async (f) => {
    await f.write(
      "bin/agent-browser",
      `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *close*) exit 0 ;;
  *'read '*|*'open '*) for url; do :; done; basename "$url" >"$FEED_TEST_DIR/current" ;;
esac
if [[ $(cat "$FEED_TEST_DIR/current") == b ]]; then
  if [[ "$*" == *'read '* ]]; then printf 'HTTP 403 Forbidden' >&2
  else printf 'net::ERR_NAME_NOT_RESOLVED' >&2; fi
  exit 1
fi
if [[ "$*" == *'open '* ]]; then exit 0; fi
jq -n '{success:true,data:{content:"A normal article describes an API change and has enough text to serve as usable content from the same feed.",status:200}}'
`,
    );
    for (let run = 0; run < 3; run++) {
      equal((await f.run()).code, 1);
      equal(await f.progress(), "old");
    }
    equal(await f.calls(), 0);
    equal(
      (await f.files("data/feed-watch/decisions", "failures.json")).length,
      0,
    );
  },
);

Deno.test("normal explanations of HTTP errors remain usable", () => {
  for (
    const heading of [
      "API authentication changes",
      "HTTP 403",
      "Access denied",
      "Page not found",
    ]
  ) {
    const body =
      `${heading}\n\nThis article explains HTTP 403 and access denied responses after OAuth requirements change. It also explains how a page not found response differs from missing write permissions. Check the required scopes before issuing a new user token.`;
    equal(usableArticle(body, { status: 200 }), true);
  }
});

for (const mode of ["read", "fallback", "heading"]) {
  integration(
    `normal error explanation is summarized through ${mode}`,
    async (f) => {
      const body = `${
        mode === "heading" ? "# HTTP 403" : "API authentication changes"
      }\n\nThis article explains HTTP 403 and access denied responses after OAuth requirements change. A page not found response has a different cause. Check the required scopes before obtaining a new user token.`;
      await f.feed(["a", "old"]);
      await f.state("old", "a");
      await f.json("page.json", { body, status: 200, blocked: false });
      if (mode === "fallback") await f.write("force-fallback", "");
      await f.write(
        "bin/agent-browser",
        `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *close*|*'open '*) exit 0 ;;
  *'read '*)
    if [[ -f "$FEED_TEST_DIR/force-fallback" ]]; then
      printf '{"success":false,"data":null,"error":"Read failed with HTTP 403"}'
      exit 1
    fi
    jq '{success:true,data:{content:.body,status:.status}}' "$FEED_TEST_DIR/page.json" ;;
  *) jq '{success:true,data:{result:.}}' "$FEED_TEST_DIR/page.json" ;;
esac
`,
      );
      for (let run = 0; run < 3; run++) equal((await f.run()).code, 0);
      equal(await f.progress(), "a");
      equal(await f.calls(), 1);
      equal((await f.read("model-input.json")).items[0].body, body);
      const ledgers = await f.files(
        "data/feed-watch/decisions",
        "failures.json",
      );
      equal(await f.read(ledgers[0]), []);
    },
  );
}

integration(
  "HTTP 404 metadata rejects a long error page without error words",
  async (f) => {
    await f.write(
      "bin/agent-browser",
      `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *close*) exit 0 ;;
  *'read '*|*'open '*) for url; do :; done; basename "$url" >"$FEED_TEST_DIR/current" ;;
esac
if [[ "$*" == *'open '* ]]; then exit 0; fi
body='The requested resource is currently unavailable at this address. Please return to the homepage and use the navigation to find an updated link.'
if [[ $(cat "$FEED_TEST_DIR/current") == a ]]; then
  if [[ "$*" == *'read '* ]]; then printf '{"success":false,"data":null,"error":"Read failed with HTTP 404"}'; exit 1; fi
  jq -n --arg body "$body" '{success:true,data:{result:{body:$body,status:404,blocked:false}}}'
else
  jq -n --arg content "$body" '{success:true,data:{content:$content,status:200}}'
fi
`,
    );
    equal((await f.run()).code, 1);
    equal((await f.run()).code, 1);
    equal((await f.run()).code, 0);
    equal(await f.progress(), "c");
    equal(
      (await f.read("model-input.json")).items.map((i: { id: string }) => i.id),
      ["b", "c"],
    );
  },
);

integration("JSON DNS errors never fall back or consume retries", async (f) => {
  await f.write(
    "bin/agent-browser",
    `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *close*) exit 0 ;;
  *'read '*|*'open '*) for url; do :; done; basename "$url" >"$FEED_TEST_DIR/current" ;;
esac
if [[ $(cat "$FEED_TEST_DIR/current") == b ]]; then
  printf '{"success":false,"data":null,"error":"net::ERR_NAME_NOT_RESOLVED"}'
  exit 1
fi
jq -n '{success:true,data:{content:"A normal article from this feed describes an API requirement change and contains enough information to be summarized.",status:200}}'
`,
  );
  for (let run = 0; run < 3; run++) {
    equal((await f.run()).code, 1);
    equal(await f.progress(), "old");
  }
  equal(
    (await f.files("data/feed-watch/decisions", "failures.json")).length,
    0,
  );
});

integration(
  "browser challenge metadata stops without consuming retries",
  async (f) => {
    await f.write(
      "bin/agent-browser",
      `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *close*|*'open '*) exit 0 ;;
  *'read '*) jq -n '{success:true,data:{content:"# Just a moment...\\n\\nChecking your browser before accessing this site. Please verify you are human before continuing to the requested page.",status:200}}' ;;
  *) jq -n '{success:true,data:{result:{body:"Verify you are human before continuing. Your browser must complete the security challenge to access the requested content.",status:200,blocked:true}}}' ;;
esac
`,
    );
    equal((await f.run()).code, 1);
    equal(await f.progress(), "old");
    equal(
      (await f.files("data/feed-watch/decisions", "failures.json")).length,
      0,
    );
  },
);
