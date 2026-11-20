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

test("blocks English prose with Japanese terms mixed in", () => {
  expect(isUntranslated(
    "The bread rises well on all 3 shelves. In every case a 強力粉 without 砂糖 gives the 生地 (こねてから寝かせる) a soft 食感 overnight.",
  )).toBe(true);
  expect(isUntranslated(
    "Merged the ブランチ into main and pushed it to origin after the checks passed.",
  )).toBe(true);
  expect(isUntranslated(
    "Updated flake.lock; tests pass; nothing committed.",
  )).toBe(true);
  expect(isUntranslated(
    "The fix is in register.ts and the tests pass on 3 machines (確認済み).",
  )).toBe(true);
});

test("passes Japanese prose full of bare identifiers and commands", () => {
  const answer = [
    "flake.nix の inputs.nixpkgs を nixos-unstable に変更し、home-manager switch --flake . --impure を実行しました。",
    "PreToolUse hook の agent-guard banned が grep -r を拒否したので、rg -n で justfile と scripts/ を検索しました。",
    "register.ts と register.test.ts だけを変更し、claude plugin test .config/claude/mods/language-guard/ が通りました。",
    "エラーは No such file or directory でした。",
  ].join("\n");
  expect(isUntranslated(answer)).toBe(false);
  expect(isUntranslated(
    "ビルド: home-manager switch --flake . --impure\nテスト: claude plugin test .config/claude/mods/language-guard/",
  )).toBe(false);
  expect(isUntranslated(
    "エラーは Failed to connect to the server after the connection timed out でした。",
  )).toBe(false);
  expect(isUntranslated(
    "エラーは Failed to connect to the server. The connection timed out. でした。",
  )).toBe(false);
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
