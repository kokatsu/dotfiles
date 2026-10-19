import { feedIds, normalizeFeed } from "./feed-entries.ts";
import { equal, run } from "./test-feed-lib.ts";

const [yq, deno] = Deno.args;
if (!yq || !deno) throw new Error("usage: test-feed-entries.ts -- <yq> <deno>");

const fixtures: [string, string, string[]][] = [
  [
    "Atom",
    "<feed><id>self</id><entry><id>a2</id></entry><entry><id>a1</id></entry></feed>",
    ["a2", "a1"],
  ],
  [
    "default namespace",
    '<feed xmlns="http://www.w3.org/2005/Atom"><id>self</id><entry><id>a1</id></entry></feed>',
    ["a1"],
  ],
  [
    "namespace prefix",
    '<atom:feed xmlns:atom="http://www.w3.org/2005/Atom"><atom:id>self</atom:id><atom:entry><atom:id>a1</atom:id></atom:entry></atom:feed>',
    ["a1"],
  ],
  [
    "RSS CDATA",
    '<rss><channel><item><guid isPermaLink="false"><![CDATA[a&b]]></guid></item></channel></rss>',
    ["a&b"],
  ],
  [
    "entities and multiline text",
    "<rss><channel><item><guid>\n a&amp;b \n</guid></item></channel></rss>",
    ["a&b"],
  ],
  ["empty Atom", "<feed><id>self</id></feed>", []],
  ["empty RSS", "<rss><channel/></rss>", []],
  [
    "missing ID",
    "<rss><channel><item><link>https://example.com/post</link></item></channel></rss>",
    [],
  ],
];

for (const [name, xml, expected] of fixtures) {
  Deno.test(name, async () => {
    const parsed = await run(yq, [
      "-p=xml",
      "-o=json",
      "--xml-raw-token=false",
      ".",
    ], xml);
    equal(parsed.code, 0);
    equal(feedIds(parsed.stdout), expected);
    const result = await run(deno, [
      "run",
      "--no-prompt",
      new URL("./feed-watch-helper.ts", import.meta.url).pathname,
      "feed-ids",
    ], parsed.stdout);
    equal(result.code, 0);
    equal(result.stdout, expected.map((id) => `${id}\n`).join(""));
  });
}

Deno.test("truncated XML is rejected by the parser", async () => {
  for (const xml of ["<feed>", "<feed><entry><id>a1</id>"]) {
    const parsed = await run(yq, [
      "-p=xml",
      "-o=json",
      "--xml-raw-token=false",
      ".",
    ], xml);
    if (parsed.code === 0) throw new Error(`accepted truncated XML: ${xml}`);
  }
});

Deno.test("lenient XML is accepted by the parser", async () => {
  for (
    const [xml, expected] of [
      [
        "<rss><channel><item><guid>a1</guid><description>x&nbsp;y</description></item></channel></rss>",
        ["a1"],
      ],
      ["<feed><id>self</id><entry><id>a1</id></feed>", ["a1"]],
    ] as const
  ) {
    const parsed = await run(yq, [
      "-p=xml",
      "-o=json",
      "--xml-raw-token=false",
      ".",
    ], xml);
    equal(parsed.code, 0);
    equal(feedIds(parsed.stdout), expected);
  }
});

Deno.test("empty or unrelated documents fail the watch CLI", async () => {
  for (
    const json of ["", "null", "{}", '{"html":{}}', '{"feed":{},"rss":{}}']
  ) {
    const result = await run(deno, [
      "run",
      "--no-prompt",
      new URL("./feed-watch-helper.ts", import.meta.url).pathname,
      "feed-ids",
    ], json);
    equal(result.code, 1);
    equal(result.stdout, "");
  }
});

Deno.test("summary normalization keeps its link fallback and fields", () => {
  const input = JSON.stringify({
    feed: {
      entry: {
        title: "Title",
        link: { "+@href": "https://example.com/post" },
        updated: "2026-10-04",
      },
    },
  });
  const expected = [{
    id: "https://example.com/post",
    title: "Title",
    link: "https://example.com/post",
    date: "2026-10-04",
  }];
  equal(normalizeFeed(input), expected);
  equal(feedIds(input), []);
});
