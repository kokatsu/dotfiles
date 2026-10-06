import { expect, test } from "claude-code/testing";
import type { SessionMessage } from "claude-code";
import { isUntranslated, requestsEnglish } from "./register.ts";

const ENGLISH =
  "I switched to main and fixed the vulnerability; nothing is committed yet.";

const row = (
  role: SessionMessage["role"],
  text: string,
  toolResults?: SessionMessage["toolResults"],
): SessionMessage => ({ role, text, toolUses: [], toolResults });

test("blocks an English final answer", async ($, on) => {
  on("session.messages", () => ({ value: [row("user", "進めて")] }));
  const result = await $.classic.Stop({
    stop_hook_active: false,
    last_assistant_message: ENGLISH,
  });
  expect(result.block).toContain("日本語で書き直して");
});

test(
  "passes a Japanese final answer on to the hooks beneath",
  async ($, on) => {
    let reached = false;
    on("classic.Stop", () => {
      reached = true;
      return {};
    });
    const result = await $.classic.Stop({
      stop_hook_active: false,
      last_assistant_message: "main にコミットしました。",
    });
    expect(reached).toBe(true);
    expect(result.block).toBeUndefined();
  },
);

test("ignores code, inline code and URLs", () => {
  const answer = [
    "コミットメッセージ案です。",
    "```",
    "fix(nix): bump source-map-js to 1.2.2 in vue-language-server lockfile",
    "```",
    "`npm audit --audit-level=high` は https://github.com/advisories/GHSA-68fv-2mgg-jv7q を報告しました。",
  ].join("\n");
  expect(isUntranslated(answer)).toBe(false);
  expect(isUntranslated("```\n" + ENGLISH + "\n```")).toBe(false);
  expect(isUntranslated("~~~sh\n" + ENGLISH + "\n~~~")).toBe(false);
});

test("leaves short Latin-only answers alone", () => {
  expect(isUntranslated("OK")).toBe(false);
  expect(isUntranslated("")).toBe(false);
});

test("reads the English request from the latest typed prompt", () => {
  const asked = [
    row("user", "lockfile を英語で説明して"),
    row("assistant", ""),
    row("user", "", [{ tool_use_id: "t1", text: "ok", isError: false }]),
  ] as SessionMessage[];
  expect(requestsEnglish(asked)).toBe(true);
  expect(requestsEnglish([row("user", "Explain it in English")])).toBe(true);
  for (
    const text of [
      "英語だけで回答してください",
      "英語のみで回答して",
      "English only",
    ]
  ) {
    expect(requestsEnglish([row("user", text)])).toBe(true);
  }
  expect(requestsEnglish([row("user", "なんで英語なのですか？")])).toBe(false);
  expect(
    requestsEnglish([row("user", "英語で書いて"), row("user", "進めて")]),
  ).toBe(false);
});

test(
  "lets an English answer through when English was asked for",
  async ($, on) => {
    on(
      "session.messages",
      () => ({ value: [row("user", "Answer in English only.")] }),
    );
    on("classic.Stop", () => ({}));
    const result = await $.classic.Stop({
      stop_hook_active: false,
      last_assistant_message: ENGLISH,
    });
    expect(result.block).toBeUndefined();
  },
);
