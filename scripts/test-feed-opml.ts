import { deepStrictEqual as equal } from "node:assert/strict";
import { execPath } from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { migrateFeedNames, parseOpml } from "./feed-opml.ts";
import { run } from "./test-feed-lib.ts";

const opmlPath = fileURLToPath(new URL("./feed-opml.ts", import.meta.url));
const helperPath = fileURLToPath(
  new URL("./feed-watch-helper.ts", import.meta.url),
);

function xml(input: string) {
  return run("yq", [
    "eval-all",
    "-p=xml",
    "-o=json",
    "--xml-raw-token=false",
    "--xml-strict-mode",
    ". as $doc ireduce ([]; . + [$doc])",
  ], input);
}

test("OPML attributes, entities, hierarchy and delimiters", () => {
  const parsed = xml(`<opml><body>
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
  const result = run(execPath, [opmlPath], parsed.stdout);
  equal(result.code, 0);
  equal(JSON.parse(result.stdout), expected);
});

test("empty OPML body is valid", () => {
  const parsed = xml("<opml><body/></opml>");
  equal(parsed.code, 0);
  equal(parseOpml(parsed.stdout), []);
});

test("invalid OPML cannot produce a partial feed list", () => {
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
    const parsed = xml(input);
    if (parsed.code !== 0) continue;
    const result = run(execPath, [opmlPath], parsed.stdout);
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

test("legacy keys migrate once without losing read or summary progress", () => {
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

test("conflicting legacy keys fail without overwriting either state", () => {
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

test("watch update migrates before counting and preserves failed fetch progress", () => {
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
  const result = run(execPath, [helperPath, "apply-check-results"], payload);
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
