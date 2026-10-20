import { currentCodeblock } from "./helix-copy-codeblock.ts";
import { equal, run } from "./test-feed-lib.ts";

const fixtures: [string, string, number[], string][] = [
  [
    "backticks",
    "before\n```ts\nconst x = 1;\n```\nafter",
    [2, 3, 4],
    "const x = 1;",
  ],
  ["tildes", "~~~sql\nselect 1;\n~~~~", [1, 2, 3], "select 1;"],
  ["nested shorter fence", "````md\n```ts\nx\n```\n````", [3], "```ts\nx\n```"],
  ["wrong closing marker", "```\nx\n~~~\ny\n```", [4], "x\n~~~\ny"],
  ["closing info", "```\nx\n```text\ny\n```", [4], "x\n```text\ny"],
  ["blank lines", "```\n\nx\n\n```", [3], "\nx\n"],
  ["blank body", "```\n\n```", [2], ""],
  ["CRLF", "```\r\n日本語\r\n```\r\n", [2], "日本語"],
  ["second block", "```\na\n```\n\n~~~\nb\n~~~", [6], "b"],
  ["indent", "  ```\n  x\n  ```", [2], "  x"],
];

for (const [name, text, cursorLines, expected] of fixtures) {
  Deno.test(name, () => {
    for (const line of cursorLines) {
      const actual = currentCodeblock(text, line);
      if (actual !== expected) {
        throw new Error(
          `${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
        );
      }
    }
  });
}

Deno.test("CLI copies only valid blocks and preserves the clipboard on failure", async () => {
  const dir = await Deno.makeTempDir({ prefix: "helix-codeblock-" });
  const clipboard = `${dir}/clipboard`;
  try {
    await Deno.writeTextFile(clipboard, "previous");
    const args = [
      "run",
      "--no-config",
      "--no-prompt",
      "--allow-run=/bin/sh",
      new URL("./helix-copy-codeblock.ts", import.meta.url).pathname,
    ];
    const copy = (text: string, line = "2", language = "markdown") =>
      run(Deno.execPath(), [
        ...args,
        line,
        language,
        "/bin/sh",
        "-c",
        'cat > "$1"',
        "sh",
        clipboard,
      ], text);
    for (
      const [text, line, language] of [
        ["plain text", "1", "markdown"],
        ["```\n```", "1", "markdown"],
        ["```\nunclosed", "2", "markdown"],
        ["```\ncode\n```", "2", "typescript"],
        ["```\ncode\n```", "invalid", "markdown"],
      ]
    ) {
      equal((await copy(text, line, language)).code, 1);
      equal(await Deno.readTextFile(clipboard), "previous");
    }
    const contents = "日本語\n$(touch should-not-exist)\n`echo literal`\n";
    equal((await copy(`\`\`\`text\n${contents}\n\`\`\``)).code, 0);
    equal(await Deno.readTextFile(clipboard), contents);
    const failedClipboard = await run(Deno.execPath(), [
      ...args,
      "2",
      "markdown",
      "/bin/sh",
      "-c",
      "exit 7",
    ], "```\ncode\n```");
    equal(failedClipboard.code, 1);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

for (
  const [name, text, line, message] of [
    ["outside", "text\n```\nx\n```", 1, "Cursor is outside a code block"],
    [
      "between",
      "```\nx\n```\ntext\n```\ny\n```",
      4,
      "Cursor is outside a code block",
    ],
    ["empty", "```\n```", 1, "Empty code block"],
    ["unclosed", "```\nx", 2, "Unclosed code block"],
    ["invalid info", "```a`b\nx", 2, "Cursor is outside a code block"],
  ] as const
) {
  Deno.test(name, () => {
    try {
      currentCodeblock(text, line);
    } catch (error) {
      if (error instanceof Error && error.message === message) return;
      throw error;
    }
    throw new Error("Expected extraction to fail");
  });
}
