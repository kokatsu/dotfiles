import { homedir } from "node:os";
import process from "node:process";

// "@earendil-works/pi-coding-agent" resolves only inside Pi, so `deno check`
// sees this subset of its ExtensionAPI instead.
type FooterData = {
  getGitBranch(): string | null;
  getExtensionStatuses(): ReadonlyMap<string, string>;
  onBranchChange(callback: () => void): () => void;
};
type Usage = {
  input: number;
  output: number;
  cost: { total: number };
};
type Entry = {
  type: string;
  message?: { role: string; usage?: Usage };
  usage?: Usage;
};
type Ctx = {
  hasUI: boolean;
  model?: { id: string; provider: string; reasoning?: boolean };
  getContextUsage():
    | { tokens: number | null; contextWindow: number; percent: number | null }
    | undefined;
  sessionManager: {
    getCwd(): string;
    getSessionName(): string | undefined;
    getEntries(): Entry[];
  };
  ui: {
    setFooter(
      factory: (
        tui: { requestRender(): void },
        theme: unknown,
        footerData: FooterData,
      ) => {
        render(width: number): string[];
        invalidate(): void;
        dispose?(): void;
      },
    ): void;
  };
};
type RateWindow = {
  used_percent: number;
  window_minutes: number;
  reset_at: number;
};
type ExtensionAPI = {
  on(event: "session_start", handler: (event: unknown, ctx: Ctx) => void): void;
  on(
    event: "provider_stream_event",
    handler: (
      event: {
        provider: string;
        data: {
          type?: string;
          rate_limits?: {
            primary: RateWindow | null;
            secondary: RateWindow | null;
          };
        };
      },
      ctx: Ctx,
    ) => void,
  ): void;
  getThinkingLevel(): string;
};

// Same palettes as cc-statusline, picked by the same CC_STATUSLINE_THEME so
// the Claude Code and Pi status lines follow one flavor.
type Palette = {
  model: string;
  green: string;
  yellow: string;
  red: string;
  dim: string;
  low: string;
  medium: string;
  high: string;
  xhigh: string;
};
const rgb = (r: number, g: number, b: number) => `\x1b[38;2;${r};${g};${b}m`;
const palettes: Record<string, Palette> = {
  "catppuccin-latte": {
    model: rgb(30, 102, 245),
    green: rgb(64, 160, 43),
    yellow: rgb(223, 142, 29),
    red: rgb(210, 15, 57),
    dim: rgb(156, 160, 176),
    low: rgb(223, 142, 29),
    medium: rgb(64, 160, 43),
    high: rgb(114, 135, 253),
    xhigh: rgb(136, 57, 239),
  },
  "catppuccin-frappe": {
    model: rgb(140, 170, 238),
    green: rgb(166, 209, 137),
    yellow: rgb(229, 200, 144),
    red: rgb(231, 130, 132),
    dim: rgb(115, 121, 148),
    low: rgb(229, 200, 144),
    medium: rgb(166, 209, 137),
    high: rgb(186, 187, 241),
    xhigh: rgb(202, 158, 230),
  },
  "catppuccin-macchiato": {
    model: rgb(138, 173, 244),
    green: rgb(166, 218, 149),
    yellow: rgb(238, 212, 159),
    red: rgb(237, 135, 150),
    dim: rgb(110, 115, 141),
    low: rgb(238, 212, 159),
    medium: rgb(166, 218, 149),
    high: rgb(183, 189, 248),
    xhigh: rgb(198, 160, 246),
  },
  "catppuccin-mocha": {
    model: rgb(137, 180, 250),
    green: rgb(166, 227, 161),
    yellow: rgb(249, 226, 175),
    red: rgb(243, 139, 168),
    dim: rgb(108, 112, 134),
    low: rgb(249, 226, 175),
    medium: rgb(166, 227, 161),
    high: rgb(180, 190, 254),
    xhigh: rgb(203, 166, 247),
  },
};
const ansi: Palette = {
  model: "\x1b[36m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  dim: "\x1b[2m",
  low: rgb(255, 193, 7),
  medium: rgb(78, 186, 101),
  high: rgb(177, 185, 249),
  xhigh: rgb(175, 135, 255),
};

// Built-in footer counts every usage-bearing entry, not only assistant messages.
function sessionUsage(entries: Entry[]) {
  let input = 0, output = 0, cost = 0;
  for (const e of entries) {
    const usage = e.type === "message" ? e.message?.usage : e.usage;
    if (!usage) continue;
    input += usage.input;
    output += usage.output;
    cost += usage.cost.total;
  }
  return { input, output, cost };
}

function tokens(n: number): string {
  if (n < 1000) return `${n}`;
  if (n < 10_000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

function threshold(p: Palette, pct: number, warn: number, crit: number) {
  if (pct >= crit) return p.red;
  if (pct >= warn) return p.yellow;
  return p.green;
}

function windowLabel(minutes: number): string {
  if (minutes === 10080) return "7d";
  return minutes % 60 === 0 ? `${minutes / 60}h` : `${minutes}m`;
}

function countdown(ms: number): string {
  if (ms <= 0) return "now";
  const min = Math.floor(ms / 60_000), h = Math.floor(min / 60);
  if (h >= 24) return `${Math.floor(h / 24)}d ${h % 24}h`;
  return h > 0 ? `${h}h ${min % 60}m` : `${min}m`;
}

function resetDate(ms: number): string {
  const d = new Date(ms);
  const p = (n: number) => `${n}`.padStart(2, "0");
  return `${p(d.getMonth() + 1)}/${p(d.getDate())} ${p(d.getHours())}:${
    p(d.getMinutes())
  }`;
}

const paint = (color: string, text: string) => `${color}${text}\x1b[0m`;

// Same cleanup as Pi's own footer: one line, escape sequences kept whole.
const oneLine = (s: string) =>
  s.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();

// Pi aliases this specifier for extensions; keeping it out of a literal
// import stops `deno check` from trying to resolve it.
const piTuiModule = "@earendil-works/pi-tui";
type PiTui = {
  visibleWidth(s: string): number;
  truncateToWidth(s: string, max: number, ellipsis?: string): string;
};

export default async function (pi: ExtensionAPI) {
  // Pi throws when a footer line is wider than the terminal, so lines are
  // measured and cut with its own grapheme- and ANSI-aware functions.
  const { visibleWidth, truncateToWidth } = await import(
    piTuiModule
  ) as PiTui;

  // Right-hand candidates go from fullest to most compact; the first that
  // fits beside the left side wins, otherwise the most compact is truncated.
  function line(left: string, rights: string[], max: number, p: Palette) {
    const ellipsis = paint(p.dim, "…");
    const lw = visibleWidth(left);
    if (lw > max) return truncateToWidth(left, max, ellipsis);
    const room = max - lw - 2;
    let right = rights.find((r) => visibleWidth(r) <= room);
    if (right === undefined && rights.length && room > 0) {
      right = truncateToWidth(rights[rights.length - 1], room, ellipsis);
    }
    if (!right) return left;
    return left + " ".repeat(max - lw - visibleWidth(right)) + right;
  }

  let ctx: Ctx | undefined;
  let limits: RateWindow[] = [];
  let redraw = () => {};

  pi.on("provider_stream_event", (event) => {
    const rl = event.data.rate_limits;
    if (event.data.type !== "codex.rate_limits" || !rl) return;
    limits = [rl.primary, rl.secondary].filter((w): w is RateWindow => !!w)
      .sort((a, b) => a.window_minutes - b.window_minutes);
    redraw();
  });

  pi.on("session_start", (_event, startCtx) => {
    ctx = startCtx;
    if (!ctx.hasUI) return;
    const p = palettes[process.env.CC_STATUSLINE_THEME ?? ""] ?? ansi;
    const sep = paint(p.dim, " | ");
    ctx.ui.setFooter((tui, _theme, footerData) => {
      redraw = () => tui.requestRender();
      const unsubscribe = footerData.onBranchChange(redraw);
      return {
        invalidate() {},
        dispose: unsubscribe,
        render(max: number): string[] {
          if (!ctx) return [];
          const sm = ctx.sessionManager;
          const home = homedir();
          let cwd = sm.getCwd();
          if (cwd === home || cwd.startsWith(`${home}/`)) {
            cwd = `~${cwd.slice(home.length)}`;
          }
          let where = `📁 ${paint(p.model, oneLine(cwd))}`;
          const branch = footerData.getGitBranch();
          if (branch) where += `${sep}🌿 ${paint(p.green, oneLine(branch))}`;
          const name = sm.getSessionName();
          if (name) where += `${sep}📛 ${paint(p.model, oneLine(name))}`;

          const model = ctx.model;
          let who = `🤖 ${paint(p.model, model?.id ?? "no-model")}`;
          if (model?.reasoning) {
            const level = pi.getThinkingLevel();
            const color = level === "minimal"
              ? p.low
              : p[level as "low" | "medium" | "high" | "xhigh"] ?? p.dim;
            who += ` ${paint(color, `⚡${level}`)}`;
          }

          const usage = ctx.getContextUsage();
          const pct = usage?.percent;
          const used = usage?.tokens == null ? "?" : tokens(usage.tokens);
          let stats = `🧠 ${
            paint(
              threshold(p, pct ?? 0, 50, 75),
              `${pct == null ? "?" : Math.round(pct)}%`,
            )
          }${paint(p.dim, ` ${used}/${tokens(usage?.contextWindow ?? 0)}`)}`;
          const { input, output, cost } = sessionUsage(sm.getEntries());
          stats += `${sep}💰 ${paint(p.yellow, `$${cost.toFixed(2)}`)}${
            paint(p.dim, ` ↑${tokens(input)} ↓${tokens(output)}`)
          }`;
          for (const text of footerData.getExtensionStatuses().values()) {
            stats += `${sep}${oneLine(text)}`;
          }

          const quota = (withDate: boolean) =>
            limits.map((w) => {
              const ms = w.reset_at * 1000 - Date.now();
              const timeColor = ms < 1_800_000
                ? p.red
                : ms < 3_600_000
                ? p.yellow
                : p.green;
              return `${w.window_minutes === 10080 ? "📅" : "🕔"} ${
                paint(p.dim, windowLabel(w.window_minutes))
              } ${
                paint(
                  threshold(p, w.used_percent, 50, 80),
                  `${w.used_percent}%`,
                )
              } ${paint(timeColor, countdown(ms))}${
                withDate ? paint(p.dim, ` ${resetDate(w.reset_at * 1000)}`) : ""
              }`;
            }).join(sep);
          const rights = model?.provider === "openai-codex" && limits.length
            ? [quota(true), quota(false)]
            : [];

          const padding = max >= 2 ? " " : "";
          const width = max - padding.length * 2;
          return [line(where, [who], width, p), line(stats, rights, width, p)]
            .map((text) => padding + text + padding);
        },
      };
    });
  });
}
