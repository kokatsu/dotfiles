import { expect, test } from "claude-code/testing";
import { lineAppender, type LineFile } from "./append.ts";

test("appends that overlap keep every line", async () => {
  const files = new Map<string, string>();
  const tick = () => Promise.resolve();
  const append = lineAppender();
  const file: LineFile = {
    exists: async (path) => (await tick(), files.has(path)),
    read: async (path) => (await tick(), files.get(path) ?? ""),
    write: async (path, text) => {
      await tick();
      files.set(path, text);
    },
  };
  await Promise.all([append(file, "log", "a"), append(file, "log", "b")]);
  expect(files.get("log")).toBe("a\nb\n");
});
