import { migrateFeedNames, parseOpml } from "./feed-opml.ts";

const [yq, deno] = Deno.args;
if (!yq || !deno) throw new Error("usage: test-feed-opml.ts -- <yq> <deno>");

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

async function run(command: string, args: string[], input: string) {
  const child = new Deno.Command(command, {
    args,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(input));
  await writer.close();
  const output = await child.output();
  return { code: output.code, stdout: new TextDecoder().decode(output.stdout) };
}

async function xml(input: string) {
  return await run(yq, [
    "eval-all",
    "-p=xml",
    "-o=json",
    "--xml-raw-token=false",
    "--xml-strict-mode",
    ". as $doc ireduce ([]; . + [$doc])",
  ], input);
}

Deno.test("OPML attributes, entities, hierarchy and delimiters", async () => {
  const parsed = await xml(`<opml><body>
    <outline text="Blog &amp; News | Today">
      <outline htmlUrl='https://example.com/?a=1&amp;b=2|3'
        xmlUrl='https://example.com/feed?a=1&amp;b=2|3'
        title="ignored" text='Alpha &amp; &quot;Beta&quot; | &#x65E5;&#26412;'/>
      <outline text="Nested"><outline text="Child" xmlUrl="child"/></outline>
      <outline text="Sibling" xmlUrl="sibling"/>
    </outline>
    <outline text="Root" xmlUrl="root"/>
  </body></opml>`);
  equal(parsed.code, 0);
  const expected = [
    {
      name: 'Alpha & "Beta" | 日本',
      category: "Blog & News | Today",
      xmlUrl: "https://example.com/feed?a=1&b=2|3",
      htmlUrl: "https://example.com/?a=1&b=2|3",
    },
    { name: "Child", category: "Nested", xmlUrl: "child", htmlUrl: "child" },
    {
      name: "Sibling",
      category: "Blog & News | Today",
      xmlUrl: "sibling",
      htmlUrl: "sibling",
    },
    { name: "Root", category: "", xmlUrl: "root", htmlUrl: "root" },
  ];
  equal(parseOpml(parsed.stdout), expected);
  const result = await run(deno, [
    "run",
    "--no-prompt",
    new URL("./feed-opml.ts", import.meta.url).pathname,
  ], parsed.stdout);
  equal(result.code, 0);
  equal(JSON.parse(result.stdout), expected);
});

Deno.test("empty OPML body is valid", async () => {
  const parsed = await xml("<opml><body/></opml>");
  equal(parsed.code, 0);
  equal(parseOpml(parsed.stdout), []);
});

Deno.test("invalid OPML cannot produce a partial feed list", async () => {
  for (
    const input of [
      "",
      "<opml><body>",
      '<opml><body><outline text="x"></body></opml>',
      "<html><body/></html>",
      "<opml/>",
      '<opml><body><outline text="ok" xmlUrl="ok"/><outline xmlUrl="missing-name"/></body></opml>',
      '<opml><body><outline text="empty-url" xmlUrl=""/></body></opml>',
    ]
  ) {
    const parsed = await xml(input);
    if (parsed.code !== 0) continue;
    const result = await run(deno, [
      "run",
      "--no-prompt",
      new URL("./feed-opml.ts", import.meta.url).pathname,
    ], parsed.stdout);
    equal(result.code, 1);
    equal(result.stdout, "");
  }
});

const entry = (name: string) => ({
  name,
  category: "New category",
  xmlUrl: "feed",
  htmlUrl: "page",
});

Deno.test("legacy keys migrate once without losing read or summary progress", () => {
  const progress = {
    last_seen_id: "seen",
    unread_count: 0,
    last_summarized_id: "summary",
  };
  const entries = [
    entry('A & "B"'),
    entry("Numeric & 日本"),
    entry("Literal &amp;"),
  ];
  const migrated = migrateFeedNames({
    "A &amp; &quot;B&quot;": progress,
    "Numeric &#38; &#x65e5;&#26412;": { ...progress, unread_count: 9 },
    "Literal &amp;amp;": progress,
  }, entries);
  equal(migrated, {
    'A & "B"': progress,
    "Numeric & 日本": { ...progress, unread_count: 9 },
    "Literal &amp;": progress,
  });
  equal(migrateFeedNames(migrated, entries), migrated);
});

Deno.test("conflicting legacy keys fail without overwriting either state", () => {
  const fixtures: Record<string, { unread_count: number }>[] = [
    { "A &amp; B": { unread_count: 5 }, "A & B": { unread_count: 2 } },
    { "A &amp; B": { unread_count: 5 }, "A &#38; B": { unread_count: 2 } },
  ];
  for (const feeds of fixtures) {
    const before = JSON.stringify(feeds);
    let failed = false;
    try {
      migrateFeedNames(feeds, [entry("A & B")]);
    } catch {
      failed = true;
    }
    equal(failed, true);
    equal(JSON.stringify(feeds), before);
  }
});

Deno.test("watch update migrates before counting and preserves failed fetch progress", async () => {
  const entries = [entry("A & B"), entry("Failed & feed")];
  const initial = {
    feeds: {
      "A &amp; B": {
        last_seen_id: "a1",
        unread_count: 4,
        last_summarized_id: "a0",
      },
      "Failed &amp; feed": {
        last_seen_id: "f1",
        unread_count: 3,
        last_summarized_id: "f0",
      },
    },
  };
  const payload = [
    JSON.stringify(initial),
    JSON.stringify(entries),
    "A & B",
    "feed",
    "page",
    "New category",
    "a2\na1",
    "",
  ].join("\0");
  const args = [
    "run",
    "--no-prompt",
    new URL("./feed-watch-helper.ts", import.meta.url).pathname,
    "apply-check-results",
  ];
  const result = await run(deno, args, payload);
  equal(result.code, 0);
  equal(JSON.parse(result.stdout).feeds, {
    "A & B": {
      last_seen_id: "a2",
      unread_count: 5,
      type: "feed",
      url: "page",
      category: "New category",
      last_summarized_id: "a0",
    },
    "Failed & feed": initial.feeds["Failed &amp; feed"],
  });
});
