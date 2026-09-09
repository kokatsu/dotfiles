import {
  makeTitle,
  type RpcClient,
  setAutomaticTitle,
} from "./codex-auto-title.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

class FakeClient implements RpcClient {
  readonly requests: Array<
    { method: string; params: Record<string, unknown> }
  > = [];
  readonly #responses: unknown[];

  constructor(responses: unknown[]) {
    this.#responses = [...responses];
  }

  request(method: string, params: Record<string, unknown>): Promise<unknown> {
    this.requests.push({ method, params });
    return Promise.resolve(this.#responses.shift());
  }

  close(): Promise<void> {
    return Promise.resolve();
  }
}

Deno.test("makeTitle normalizes a prompt and prefixes a branch issue", () => {
  assertEquals(
    makeTitle(
      ["  Codex のセッション名を   自動設定してください。 https://example.com/x "],
      "/work/dotfiles",
      "feature/123-auto-title",
    ),
    "#123 Codex のセッション名を 自動設定してください",
  );
});

Deno.test("makeTitle uses the working directory for an empty prompt", () => {
  assertEquals(
    makeTitle(["https://example.com"], "/work/dotfiles/", undefined),
    "dotfiles",
  );
});

Deno.test("makeTitle truncates titles by grapheme", () => {
  assertEquals(
    makeTitle(["あ".repeat(45)], "/work/dotfiles", undefined),
    `${"あ".repeat(39)}…`,
  );
});

Deno.test("makeTitle does not treat a date branch as an issue", () => {
  assertEquals(
    makeTitle(["セッション名"], "/work/dotfiles", "20260909"),
    "セッション名",
  );
});

Deno.test("setAutomaticTitle sets an unnamed root thread", async () => {
  const client = new FakeClient([
    { thread: { name: null, gitInfo: { branch: "feature/#456-title" } } },
    { thread: { name: null } },
    {},
  ]);
  const changed = await setAutomaticTitle(
    {
      type: "agent-turn-complete",
      "thread-id": "thread-1",
      cwd: "/work/dotfiles",
      "input-messages": ["セッション名を設定する"],
    },
    client,
  );

  assertEquals(changed, true);
  assertEquals(client.requests.at(-1), {
    method: "thread/name/set",
    params: { threadId: "thread-1", name: "#456 セッション名を設定する" },
  });
});

Deno.test("setAutomaticTitle preserves an existing manual name", async () => {
  const client = new FakeClient([{ thread: { name: "手動の名前" } }]);
  const changed = await setAutomaticTitle(
    {
      type: "agent-turn-complete",
      "thread-id": "thread-1",
      cwd: "/work/dotfiles",
      "input-messages": ["新しい名前"],
    },
    client,
  );

  assertEquals(changed, false);
  assertEquals(client.requests.length, 1);
});

Deno.test("setAutomaticTitle skips child and ephemeral threads", async () => {
  for (const thread of [{ parentThreadId: "parent" }, { ephemeral: true }]) {
    const client = new FakeClient([{ thread }]);
    const changed = await setAutomaticTitle(
      {
        type: "agent-turn-complete",
        "thread-id": "thread-1",
        "input-messages": ["名前"],
      },
      client,
    );
    assertEquals(changed, false);
    assertEquals(client.requests.length, 1);
  }
});

Deno.test("setAutomaticTitle loses a race to manual rename", async () => {
  const client = new FakeClient([
    { thread: { name: null } },
    { thread: { name: "先に付いた名前" } },
  ]);
  const changed = await setAutomaticTitle(
    {
      type: "agent-turn-complete",
      "thread-id": "thread-1",
      "input-messages": ["自動の名前"],
    },
    client,
  );

  assertEquals(changed, false);
  assertEquals(client.requests.length, 2);
});
