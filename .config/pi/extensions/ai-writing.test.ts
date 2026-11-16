import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { test } from "node:test";
import check from "./ai-writing.ts";

function setup() {
  let handler: Parameters<Parameters<typeof check>[0]["on"]>[1] | undefined;
  check({
    on(_event, callback) {
      handler = callback;
    },
  });
  assert.ok(handler);
  return handler;
}

// The stub stands in for check-ai-writing.sh, whose own branches
// test-ai-writing-hook.sh covers. It records its stdin and prints $REPLY_JSON.
function withStub(fn: (dir: string) => Promise<void>) {
  const dir = mkdtempSync(path.join(tmpdir(), "pi-ai-writing-test-"));
  const original = process.env.XDG_CONFIG_HOME;
  mkdirSync(path.join(dir, "ai-writing"));
  writeFileSync(
    path.join(dir, "ai-writing/check-ai-writing.sh"),
    `cat > "${dir}/payload.json"; printf '%s' "$REPLY_JSON"\n`,
  );
  process.env.XDG_CONFIG_HOME = dir;
  return fn(dir).finally(() => {
    if (original === undefined) delete process.env.XDG_CONFIG_HOME;
    else process.env.XDG_CONFIG_HOME = original;
    delete process.env.REPLY_JSON;
    rmSync(dir, { recursive: true, force: true });
  });
}

const written = { type: "text", text: "Successfully wrote 5 bytes" };

test("Pi passes the resolved path and appends a finding to the result", () =>
  withStub(async (dir) => {
    const handler = setup();
    process.env.REPLY_JSON = JSON.stringify({
      decision: "block",
      reason: "line 1 finding",
    });
    const result = await handler({
      toolName: "write",
      input: { path: "@doc.md" },
      content: [written],
      isError: false,
    }, { cwd: dir });
    assert.deepEqual(
      JSON.parse(readFileSync(path.join(dir, "payload.json"), "utf8")),
      {
        tool_input: { file_path: path.join(dir, "doc.md") },
        cwd: dir,
      },
    );
    assert.deepEqual(result?.content, [written, {
      type: "text",
      text: "line 1 finding",
    }]);

    process.env.REPLY_JSON = JSON.stringify({
      systemMessage: "textlint failed",
    });
    const failed = await handler({
      toolName: "edit",
      input: { path: "doc.md" },
      content: [written],
      isError: false,
    }, { cwd: dir });
    assert.deepEqual(failed?.content, [written, {
      type: "text",
      text: "textlint failed",
    }]);
  }));

test("Pi leaves clean, failed, and other tool results alone", () =>
  withStub(async (dir) => {
    const handler = setup();
    const ctx = { cwd: dir };
    assert.equal(
      await handler({
        toolName: "write",
        input: { path: "doc.md" },
        content: [written],
        isError: false,
      }, ctx),
      undefined,
    );
    process.env.REPLY_JSON = JSON.stringify({
      decision: "block",
      reason: "finding",
    });
    assert.equal(
      await handler({
        toolName: "write",
        input: { path: "doc.md" },
        content: [written],
        isError: true,
      }, ctx),
      undefined,
    );
    assert.equal(
      await handler({
        toolName: "bash",
        input: { command: "true" },
        content: [],
        isError: false,
      }, ctx),
      undefined,
    );
  }));
