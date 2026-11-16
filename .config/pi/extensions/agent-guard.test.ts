import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { test } from "node:test";
import guard from "./agent-guard.ts";

function setup() {
  let handler: Parameters<Parameters<typeof guard>[0]["on"]>[1] | undefined;
  guard({
    on(_event, callback) {
      handler = callback;
    },
  });
  assert.ok(handler);
  return handler;
}

test("Pi guard checks tool calls with the real agent-guard", async () => {
  const handler = setup();
  const ctx = { cwd: process.cwd() };
  for (
    const command of [
      "gh api -X GET repos/o/r",
      "/usr/bin/gh api -X GET repos/o/r",
      "gh api -X GET repos/o/r --jq '.name' | head -n 1",
      'gh api -X GET "repos/$repo"',
      "rg pattern .",
      "git diff --output=/tmp/pi-guard-test.diff",
    ]
  ) {
    assert.equal(
      await handler({ toolName: "bash", input: { command } }, ctx),
      undefined,
      command,
    );
  }
  for (
    const command of [
      "gh api repos/o/r",
      "gh api -X POST repos/o/r/issues -f title=probe",
      "gh -X DELETE api repos/o/r",
      "gh --method DELETE api repos/o/r",
      "gh --method=DELETE api repos/o/r",
      "gh --hostname github.com api -X DELETE repos/o/r",
      "gh -X POST api repos/o/r/issues -f title=x",
      "/usr/bin/gh -X DELETE api repos/o/r",
      "env gh -X DELETE api repos/o/r",
      "gh -X GET api repos/o/r",
      "/usr/bin/gh api -X POST repos/o/r/issues -f title=probe",
      "env gh api -X DELETE repos/o/r",
      "doas gh api repos/o/r",
      "gh api -X DELETE repos/o/r",
      "gh api -X GET repos/o/r -X DELETE",
      "gh api -X GET repos/o/r --input payload.json",
      "gh api -X GET repos/o/r --hostname evil.example",
      "gh api -X GET https://evil.example/x",
      'gh api -X GET "$@"',
      "bash -c 'gh api -X POST repos/o/r'",
      "gh api -X GET repos/o/r > /tmp/pi-guard-test.json",
      "gh api -X GET repos/o/r && touch /tmp/pi-guard-test",
      "npm install -g example",
      "rm -rf build",
      "herdr agent prompt w1:p1 probe",
      'echo "unterminated',
    ]
  ) {
    const result = await handler({ toolName: "bash", input: { command } }, ctx);
    assert.equal(result?.block, true, command);
    assert.ok(result?.reason, command);
  }
  for (const input of [{}, { command: null }, { command: 42 }]) {
    assert.equal(
      (await handler({ toolName: "bash", input }, ctx))?.block,
      true,
    );
  }
  for (const toolName of ["edit", "write"]) {
    assert.equal(
      (await handler(
        { toolName, input: { path: "/nix/store/pi-guard-test" } },
        ctx,
      ))
        ?.block,
      true,
    );
    assert.equal(
      await handler({ toolName, input: { path: "/tmp/pi-guard-test" } }, ctx),
      undefined,
    );
  }
  for (const toolName of ["read", "grep", "find", "ls", "subagent"]) {
    assert.equal(await handler({ toolName, input: {} }, ctx), undefined);
  }
  for (const toolName of ["powershell", "mcp", "Bash", "Subagent", ""]) {
    const result = await handler({ toolName, input: { command: "ls" } }, ctx);
    assert.equal(result?.block, true, toolName);
    assert.ok(result?.reason, toolName);
  }
});

test("Pi blocks when agent-guard is missing or exits without a verdict", async () => {
  const handler = setup();
  const originalPath = process.env.PATH;
  const dir = mkdtempSync(path.join(tmpdir(), "pi-guard-test-"));
  try {
    process.env.PATH = dir;
    const event = { toolName: "bash", input: { command: "echo probe" } };
    const ctx = { cwd: dir };
    assert.equal((await handler(event, ctx))?.block, true);
    writeFileSync(path.join(dir, "agent-guard"), "#!/bin/sh\nexit 1\n", {
      mode: 0o700,
    });
    assert.equal((await handler(event, ctx))?.block, true);
  } finally {
    if (originalPath === undefined) delete process.env.PATH;
    else process.env.PATH = originalPath;
    rmSync(dir, { recursive: true, force: true });
  }
});
