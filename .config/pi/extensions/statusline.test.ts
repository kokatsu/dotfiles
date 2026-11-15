import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import process from "node:process";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

// Pi resolves this specifier through a jiti alias; outside Pi it has to point
// at the installed copy, which also serves as the width oracle because Pi
// throws when a rendered line is wider than the terminal.
const piTui = pathToFileURL(process.env.PI_TUI ?? "").href;
registerHooks({
  resolve: (specifier, context, next) =>
    specifier === "@earendil-works/pi-tui"
      ? { url: piTui, shortCircuit: true }
      : next(specifier, context),
});
const { visibleWidth } = await import(piTui) as {
  visibleWidth(s: string): number;
};
const { default: statusline } = await import("./statusline.ts");

type Render = (width: number) => string[];

async function setup(opts: {
  cwd: string;
  sessionName?: string;
  branch?: string;
  statuses?: Map<string, string>;
}) {
  // deno-lint-ignore no-explicit-any
  const handlers: Record<string, (event: any, ctx: any) => void> = {};
  let render: Render | undefined;
  const ctx = {
    hasUI: true,
    model: { id: "gpt-6.1-sol", provider: "openai-codex", reasoning: true },
    getContextUsage: () => ({
      tokens: 61_000,
      contextWindow: 500_000,
      percent: 12.3,
    }),
    sessionManager: {
      getCwd: () => opts.cwd,
      getSessionName: () => opts.sessionName,
      getEntries: () => [],
    },
    ui: {
      // deno-lint-ignore no-explicit-any
      setFooter(factory: any) {
        render = factory({ requestRender() {} }, {}, {
          getGitBranch: () => opts.branch ?? "main",
          getExtensionStatuses: () => opts.statuses ?? new Map(),
          onBranchChange: () => () => {},
        }).render;
      },
    },
  };
  await statusline({
    // deno-lint-ignore no-explicit-any
    on: (event: string, handler: any) => {
      handlers[event] = handler;
    },
    getThinkingLevel: () => "medium",
  });
  handlers.session_start({}, ctx);
  handlers.provider_stream_event({
    provider: "openai-codex",
    data: {
      type: "codex.rate_limits",
      rate_limits: {
        primary: { used_percent: 42, window_minutes: 300, reset_at: 0 },
        secondary: { used_percent: 5, window_minutes: 10080, reset_at: 0 },
      },
    },
  }, ctx);
  assert.ok(render);
  return render;
}

const cases = [
  { name: "ascii", cwd: "/tmp/project" },
  { name: "japanese session name", cwd: "/tmp/project", sessionName: "日本語" },
  { name: "japanese path", cwd: "/tmp/日本語のとても長いディレクトリ名" },
  { name: "japanese branch", cwd: "/tmp/project", branch: "機能/ステータス行" },
  {
    name: "emoji presentation selector",
    cwd: "/tmp/project",
    sessionName: "❤️☀️",
  },
  {
    name: "themed status",
    cwd: "/tmp/project",
    statuses: new Map([["a", "\x1b[2mReady\x1b[22m ".repeat(20)]]),
  },
];

for (const c of cases) {
  test(`footer fits the terminal: ${c.name}`, async () => {
    const render = await setup(c);
    for (const width of [20, 40, 80, 81, 120]) {
      for (const line of render(width)) {
        assert.ok(
          visibleWidth(line) <= width,
          `${visibleWidth(line)} > ${width}: ${JSON.stringify(line)}`,
        );
      }
    }
  });
}

test("themed status keeps its escape sequences whole", async () => {
  const render = await setup({
    cwd: "/tmp/project",
    statuses: new Map([["a", "\x1b[2mReady\x1b[22m"]]),
  });
  const line = render(120)[1];
  // deno-lint-ignore no-control-regex
  assert.match(line.replace(/\x1b\[[0-9;]*m/g, ""), /\| Ready /);
  // deno-lint-ignore no-control-regex
  assert.doesNotMatch(line, /(?<!\x1b)\[[0-9;]*m/);
});
