import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { sep } from "node:path";
import { argv, env, stdin, stdout } from "node:process";
import { createInterface } from "node:readline";

const uri = "ui://dotfiles-statusline/footer";
const tool = {
  name: "statusline",
  title: "Dotfiles status line",
  inputSchema: { type: "object" },
  _meta: {
    "openai/ui": { entrypoints: [{ type: "statusline", resourceUri: uri }] },
  },
};
const [, , git, gh] = argv;

if (!git || !gh) throw new Error("Expected paths to git and gh");

function record(value: unknown): Record<string, unknown> {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return Object.fromEntries(Object.entries(value));
  }
  return {};
}

function string(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

const colors = record(JSON.parse(env.CODEX_STATUSLINE_COLORS ?? "{}"));
const icons = record(JSON.parse(env.CODEX_STATUSLINE_ICONS ?? "{}"));

function cachedLookup<Key extends unknown[], Value>(
  refreshMs: number,
  fetch: (...key: Key) => Promise<Value>,
) {
  let cached:
    | { key: string; value: Value | undefined; refreshAt: number }
    | undefined;
  let activeKey: string;
  const pending = new Set<string>();
  return (...key: Key) => {
    const cacheKey = JSON.stringify(key);
    activeKey = cacheKey;
    const match = cached?.key === cacheKey;
    // Codex times out resources/read after one second, even when gh is still running.
    if (
      !pending.has(cacheKey) &&
      (!match || (cached && performance.now() >= cached.refreshAt))
    ) {
      pending.add(cacheKey);
      void fetch(...key).catch(() => undefined).then((value) => {
        if (activeKey === cacheKey) {
          cached = {
            key: cacheKey,
            value,
            refreshAt: performance.now() + refreshMs,
          };
        }
        pending.delete(cacheKey);
      });
    }
    return match ? cached?.value : undefined;
  };
}

function command(
  cwd: string,
  executable: string,
  args: string[],
  timeout: number,
) {
  return new Promise<string | undefined>((resolve) => {
    const child = execFile(
      executable,
      args,
      {
        cwd,
        env: { ...env, GIT_TERMINAL_PROMPT: "0", GH_PROMPT_DISABLED: "1" },
        timeout,
        killSignal: "SIGKILL",
      },
      (error, output) =>
        resolve(error ? undefined : output.replace(/\n+$/, "")),
    );
    child.stdin?.end();
  });
}

const branchArgs = ["branch", "--show-current"];
const localBranchPrefix = "refs/heads/";
const gitInfo = cachedLookup(
  2_000,
  async (cwd: string, showChanges: boolean) => {
    const gitOutput = (...args: string[]) => command(cwd, git, args, 1_000);
    const branch = await gitOutput(...branchArgs);
    if (branch === undefined || !showChanges) return { branch };

    const remotes = (await gitOutput("remote"))?.split("\n").filter(Boolean) ??
      [];
    const refs = remotes.toSorted((a, b) =>
      Number(b === "origin") - Number(a === "origin")
    )
      .map((remote) => `refs/remotes/${remote}/HEAD`);
    refs.push("refs/heads/main", "refs/heads/master");
    let base: string | undefined;
    let comparison: string | undefined;
    for (const ref of refs) {
      base = await gitOutput("merge-base", "HEAD", ref);
      if (!base) continue;
      comparison = ref.startsWith(localBranchPrefix)
        ? ref.slice(localBranchPrefix.length)
        : (await gitOutput("symbolic-ref", "--short", ref) ??
          ref.slice("refs/remotes/".length));
      break;
    }
    if (!base || !comparison) return { branch };

    const stats = await gitOutput(
      "diff",
      "--no-ext-diff",
      "--no-textconv",
      "--numstat",
      base,
      "HEAD",
      "--",
    );
    if (stats === undefined) return { branch };
    let added = 0;
    let removed = 0;
    for (const line of stats.split("\n")) {
      const [additions, deletions] = line.split("\t", 2);
      if (
        additions && deletions && /^\d+$/.test(additions) &&
        /^\d+$/.test(deletions)
      ) {
        added += Number(additions);
        removed += Number(deletions);
      }
    }
    return {
      branch,
      changes: { added, removed, comparison, hasEntries: stats !== "" },
    };
  },
);

const openPr = cachedLookup(60_000, async (cwd: string, branch: string) => {
  if (await command(cwd, git, branchArgs, 1_000) !== branch) return;
  const output = await command(cwd, gh, [
    "pr",
    "view",
    "--json",
    "number,state,url",
  ], 4_000);
  if (!output || await command(cwd, git, branchArgs, 1_000) !== branch) return;
  const pr = record(JSON.parse(output));
  const id = number(pr.number);
  const href = string(pr.url);
  if (pr.state === "OPEN" && id !== undefined && href) {
    return { label: `PR #${id}`, href };
  }
});

function compactTokens(count: number) {
  if (count >= 1_000_000) return `${Number((count / 1_000_000).toFixed(1))}M`;
  if (count >= 1_000) return `${Number((count / 1_000).toFixed(1))}K`;
  return String(count);
}

function limitLabel(
  account: Record<string, unknown>,
  minutes: number,
  label: string,
) {
  const limits = account.rate_limits;
  if (!Array.isArray(limits)) return;
  const snapshot = limits.map(record).find((limit) =>
    limit.limit_id === "codex"
  );
  if (!snapshot) return;
  const windows = [
    record(snapshot.primary_limit),
    record(snapshot.secondary_limit),
  ];
  const window = windows.find((window) => window.window_minutes === minutes);
  const usedPercent = number(window?.used_percent);
  if (usedPercent !== undefined) {
    const remaining = 100 - Math.min(100, Math.max(0, usedPercent));
    return `${label} ${remaining.toFixed(0)}% left`;
  }
}

function displayPath(cwd: string) {
  const home = homedir();
  return cwd === home || cwd.startsWith(home + sep)
    ? `~${cwd.slice(home.length)}`
    : cwd;
}

function coloredText(value: string, item: string, fallback = "primary") {
  return {
    type: "text",
    props: { color: string(colors[item]) ?? fallback },
    children: [value],
  };
}

function render(state: Record<string, unknown>) {
  const configured = record(state.config).statusline_items;
  const items = Array.isArray(configured)
    ? configured.filter((item): item is string => typeof item === "string")
    : [];
  const thread = record(state.thread);
  const model = record(thread.model);
  const usage = record(thread.usage);
  const account = record(state.account);
  const context = record(usage.context);
  const total = record(usage.total);
  const used = number(context.used_percentage);
  const usedPercent = used === undefined ? undefined : Math.round(used);
  const window = number(context.context_window_size);
  const cwd = string(record(thread.workspace).cwd);
  const showChanges = items.includes("branch-changes");
  const showPr = items.includes("pull-request-number");
  const info = cwd && (showChanges || showPr || items.includes("git-branch"))
    ? gitInfo(cwd, showChanges)
    : undefined;
  const pr = cwd && info?.branch && showPr
    ? openPr(cwd, info.branch)
    : undefined;
  const changes = info?.changes;
  const changeLabel = changes && (changes.added || changes.removed
    ? [
      coloredText(`+${changes.added}`, "branch-additions", "green"),
      " ",
      coloredText(`-${changes.removed}`, "branch-deletions", "red"),
      coloredText(` vs ${changes.comparison}`, "branch-changes"),
    ]
    : `${
      changes.hasEntries ? "No line changes" : "No committed changes"
    } vs ${changes.comparison}`);
  const inputTokens = number(total.total_input_tokens);
  const outputTokens = number(total.output_tokens);
  const tokens = (inputTokens ?? 0) + (outputTokens ?? 0);
  const modelLabel = [
    string(model.display_name),
    string(model.reasoning_level),
    string(model.service_tier_display_name)?.toLowerCase(),
  ].filter(Boolean).join(" ");

  const values: Record<
    string,
    string | (string | ReturnType<typeof coloredText>)[] | undefined
  > = {
    "model-with-reasoning": modelLabel,
    "current-dir": cwd ? displayPath(cwd) : undefined,
    "git-branch": info?.branch,
    "pull-request-number": pr?.label,
    "branch-changes": changeLabel,
    "context-remaining": usedPercent === undefined
      ? undefined
      : `Context ${100 - usedPercent}% left`,
    "context-used": usedPercent === undefined
      ? undefined
      : `Context ${usedPercent}% used`,
    "context-window-size": window === undefined
      ? undefined
      : `${compactTokens(window)} window`,
    "used-tokens": tokens ? `${compactTokens(tokens)} used` : undefined,
    "total-input-tokens": inputTokens === undefined
      ? undefined
      : `${compactTokens(inputTokens)} in`,
    "total-output-tokens": outputTokens === undefined
      ? undefined
      : `${compactTokens(outputTokens)} out`,
    "five-hour-limit": limitLabel(account, 300, "5h"),
    "weekly-limit": limitLabel(account, 10_080, "Weekly"),
    "codex-version": string(record(state.app).cli_version),
  };

  const children = [];
  for (const item of items) {
    const value = Object.hasOwn(values, item) ? values[item] : undefined;
    if (!value) continue;
    if (children.length) children.push("·");
    const icon = string(icons[item]);
    const prefix = icon ? `${icon} ` : "";
    const text = typeof value === "string"
      ? coloredText(prefix + value, item)
      : { type: "text", children: prefix ? [prefix, ...value] : value };
    children.push(
      item === "pull-request-number" && pr
        ? { type: "link", props: { href: pr.href }, children: [text] }
        : text,
    );
  }
  return children.length
    ? { type: "row", props: { gap: 1, wrap: "wrap" }, children }
    : null;
}

function respond(method: string, params: Record<string, unknown>) {
  switch (method) {
    case "initialize":
      return {
        protocolVersion: "2025-06-18",
        capabilities: { tools: {}, resources: {} },
        serverInfo: { name: "dotfiles-statusline", version: "1.0" },
      };
    case "ping":
      return {};
    case "tools/list":
      return { tools: [tool] };
    case "tools/call":
      if (params.name === tool.name) {
        return { content: [{ type: "text", text: uri }] };
      }
      return;
    case "resources/list":
      return {
        resources: [{ name: "footer", uri, mimeType: "application/json" }],
      };
    case "resources/templates/list":
      return { resourceTemplates: [] };
    case "resources/read": {
      if (params.uri !== uri) return;
      const state = record(
        record(params._meta)["com.openai/codex-statusline-state"],
      );
      return {
        contents: [{
          uri,
          mimeType: "application/json",
          text: JSON.stringify(render(state)),
        }],
      };
    }
  }
}

function handle(line: string) {
  const jsonrpc = "2.0";
  let request: Record<string, unknown>;
  try {
    request = record(JSON.parse(line));
  } catch {
    return {
      jsonrpc,
      id: null,
      error: { code: -32700, message: "Parse error" },
    };
  }
  if (typeof request.method !== "string") {
    return {
      jsonrpc,
      id: null,
      error: { code: -32600, message: "Invalid request" },
    };
  }
  if (!Object.hasOwn(request, "id")) return;
  try {
    const result = respond(request.method, record(request.params));
    if (result === undefined) {
      return {
        jsonrpc,
        id: request.id,
        error: { code: -32601, message: "Method not found" },
      };
    }
    return { jsonrpc, id: request.id, result };
  } catch {
    return {
      jsonrpc,
      id: request.id,
      error: { code: -32603, message: "Internal error" },
    };
  }
}

for await (
  const line of createInterface({ input: stdin, crlfDelay: Infinity })
) {
  const reply = handle(line);
  if (reply) stdout.write(`${JSON.stringify(reply)}\n`);
}
