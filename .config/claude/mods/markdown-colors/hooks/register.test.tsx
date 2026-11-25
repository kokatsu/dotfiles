import { expect, test } from "claude-code/testing";

import { parse, strongRuns } from "./register";

function draw(text: string) {
  return {
    surface: "terminal" as const,
    component: "AssistantMessage" as const,
    requestId: "m1",
    viewport: { columns: 84, rows: 40 },
    props: { text, isFirstOfReply: false },
  };
}

test("headings split out, fenced ones stay prose", () => {
  const text = [
    "intro",
    "## Plan `x` **y** *z* ~~w~~",
    "body",
    "```sh",
    "# comment",
    "```",
    "### Done ###",
  ].join("\n");
  expect(parse(text)).toEqual([
    { markdown: "intro" },
    { level: 2, title: "Plan x y z w" },
    { markdown: "body\n```sh\n# comment\n```" },
    { level: 3, title: "Done" },
  ]);
});

test("code spans in a heading keep their marks", () => {
  expect(parse("# Match `**/*.ts` and **[docs](u)**")).toEqual([
    { level: 1, title: "Match **/*.ts and docs" },
  ]);
  expect(parse("# ``**/*.ts`` or `` a`*b* ``")).toEqual([
    { level: 1, title: "**/*.ts or a`*b*" },
  ]);
});

test("a reply without headings goes to the engine whole", async ($, on) => {
  const seen: string[] = [];
  on("ui.render", (_$, e) => {
    if (e.component === "AssistantMessage") seen.push(e.props.text);
    return { type: "Text", props: {}, children: [] };
  });
  await $.ui.render(draw("plain\n#hashtag"));
  expect(seen).toEqual(["plain\n#hashtag"]);
});

test(
  "a heading is drawn as colored Text, prose through the engine",
  async ($, on) => {
    const seen: string[] = [];
    on("ui.render", (_$, e) => {
      if (e.component === "AssistantMessage") seen.push(e.props.text);
      return { type: "Text", props: {}, children: ["engine"] };
    });
    const ui = await $.ui.mount({
      ...draw("# Title\nbody"),
      plugin: "markdown-colors",
    });
    expect(seen).toEqual(["body"]);
    expect((await ui.find({ type: "Text", text: "Title" }))?.text).toBe(
      "Title",
    );
    await ui.unmount();
  },
);

test("lists and lone strong lines split out", () => {
  const text = [
    "intro",
    "",
    "- a",
    "- **b** c",
    "  1. d",
    "",
    "**Note**: x",
    "",
    "tail",
  ].join("\n");
  expect(parse(text)).toEqual([
    { markdown: "intro" },
    {
      items: [
        { indent: 0, marker: "-", text: "a" },
        { indent: 0, marker: "-", text: "**b** c" },
        { indent: 2, marker: "1.", text: "d" },
      ],
    },
    {
      runs: [
        { text: "Note", isStrong: true },
        { text: ": x" },
      ],
    },
    { markdown: "tail" },
  ]);
});

test("a list with continuation lines goes to the engine whole", () => {
  const text = "a\n\n- x\n  more\n- y\n\nb";
  expect(parse(text)).toEqual([{ markdown: text }]);
  const lazy = "- x\nlazy\n- y";
  expect(parse(lazy)).toEqual([{ markdown: lazy }]);
  const loose = "- x\n\n  more\n\n- y\n\nb";
  expect(parse(loose)).toEqual([{ markdown: loose }]);
});

test("strong lines that are not whole paragraphs stay with the engine", () => {
  for (
    const text of [
      "x\n**a** b",
      "**a** b\nx",
      "**a**\n---",
      "> **a**",
      "| **a** |",
      "```\n**a**\n- b\n```",
      "foo\n2. bar",
      "**a** b\n2. c",
    ]
  ) {
    expect(parse(text)).toEqual([{ markdown: text }]);
  }
});

test("only lines whose sole markdown is ** pairs and code become runs", () => {
  expect(strongRuns("これは**強調**です")).toEqual([
    { text: "これは" },
    { text: "強調", isStrong: true },
    { text: "です" },
  ]);
  expect(strongRuns("**修正**: `~/.x_y` と `` a`**b** ``")).toEqual([
    { text: "修正", isStrong: true },
    { text: ": " },
    { text: "~/.x_y", isCode: true },
    { text: " と " },
    { text: "a`**b**", isCode: true },
  ]);
  expect(strongRuns("、**`x`**: `` \u00a0 ``")).toEqual([
    { text: "、" },
    { text: "x", isCode: true, isStrong: true },
    { text: ": " },
    { text: "\u00a0", isCode: true },
  ]);
  expect(strongRuns("**a `b`** c")).toEqual([
    { text: "a ", isStrong: true },
    { text: "b", isCode: true, isStrong: true },
    { text: " c" },
  ]);
  for (
    const line of [
      "plain",
      "`b`",
      "`**b**`",
      "**a** `b",
      "prefix**`x`**",
      "**`x`**です",
      "prefix**!`x`**",
      "**`x`!**suffix",
      "**「強調」**です",
      "**a** \\`b`",
      "**a** [b](c)",
      "**a** https://x.y",
      "**a** *b*",
      "a ** b ** c",
      "**a** snake_case",
      "**a** &amp;",
    ]
  ) {
    expect(strongRuns(line)).toBeUndefined();
  }
});

test("a list is drawn with colored markers, bodies through Markdown", async ($) => {
  const ui = await $.ui.mount({
    ...draw("- **a** b\n- `c`"),
    plugin: "markdown-colors",
  });
  expect((await ui.find({ type: "Text", text: "a b" }))?.text).toBe("a b");
  expect((await ui.find({ type: "Markdown", text: "`c`" }))?.text).toBe("`c`");
  await ui.unmount();
});

test(
  "the reply's bullet follows the OS without running a program",
  async ($, on) => {
    on("process.run", () => {
      throw new Error("aborted");
    });
    on("session.machine", () => ({
      value: {
        sysname: "Darwin",
        release: "24.1.0",
        machine: "arm64",
        packageManagers: [],
        runtimes: [],
      },
    }));
    const ui = await $.ui.mount({
      ...draw("# Title"),
      props: { text: "# Title", isFirstOfReply: true },
      plugin: "markdown-colors",
    });
    expect((await ui.find({ type: "Text", text: "⏺" }))?.text).toBe("⏺");
    await ui.unmount();
  },
);
