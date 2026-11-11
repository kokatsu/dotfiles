import type { Register } from "claude-code";

const FETCH_MS = 5 * 60 * 1000;
const RENDER_MS = 60 * 1000;
const FABLE_LINE = /Current week \(Fable\): (\d+)% used(?: · resets (.+))?/;
// /usage adds the year only when the reset falls in another year. Claude Code
// releases differ in joining the date to the time with ", " or " at ".
const RESET_TEXT =
  /^(?:([A-Z][a-z]{2}) (\d{1,2}),? (?:(\d{4}),? )?(?:at )?)?(\d{1,2})(?::(\d{2}))?(am|pm)/;
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];
const SNAP_MS = 2 * 60 * 1000;

// disableAllHooks keeps the child from firing the user's SessionStart/Stop
// hooks (herdr session reports, notifications) and from loading mods, this one included.
const USAGE_ARGV = [
  "claude",
  "-p",
  "--no-session-persistence",
  "--settings",
  '{"disableAllHooks":true}',
  "/usage",
];
// mkdir is atomic, so of the sessions sharing the cache, the one that creates
// the directory for the current slot is the only one to run /usage in it.
const CLAIM_SCRIPT = 'mkdir -p "$1" && mkdir "$1/$2" && ' +
  'find "$1" -mindepth 1 -maxdepth 1 ! -name "$2" -exec rmdir {} +';
const ENV_ARGV = [
  "sh",
  "-c",
  'date +%z; printf %s "${XDG_CACHE_HOME:-$HOME/.cache}"',
];

// cc-statusline's default (Catppuccin Mocha) colors and thresholds, so this line
// matches the 7d line the statusLine command prints above it.
const DIM = "\x1b[38;2;108;112;134m";
const GREEN = "\x1b[38;2;166;227;161m";
const YELLOW = "\x1b[38;2;249;226;175m";
const RED = "\x1b[38;2;243;139;168m";
const RESET = "\x1b[0m";

type Reading = { percent: number; resetsAtMs?: number };

const parseOffsetMs = (z: string) => {
  const m = /^([+-])(\d{2})(\d{2})$/.exec(z.trim());
  if (!m) return 0;
  return (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3])) * 60 *
    1000;
};

// /usage prints the reset in the machine's local zone, e.g. "Nov 17, 8am (Asia/Tokyo)".
const parseResetMs = (text: string, nowMs: number, offsetMs: number) => {
  const m = RESET_TEXT.exec(text);
  if (!m) return undefined;
  const local = new Date(nowMs + offsetMs);
  const month = m[1] ? MONTHS.indexOf(m[1]) : local.getUTCMonth();
  const day = m[2] ? Number(m[2]) : local.getUTCDate();
  const year = m[3] ? Number(m[3]) : local.getUTCFullYear();
  const hour = (Number(m[4]) % 12) + (m[6] === "pm" ? 12 : 0);
  return Date.UTC(year, month, day, hour, Number(m[5] ?? 0)) - offsetMs;
};

// /usage reads a reset that can land just before the minute (7:59am for 8am),
// while the weekly window's reset comes from the response headers to the second.
const snapToWeekly = (ms: number | undefined, weeklyResetsAt?: string) => {
  if (ms === undefined || weeklyResetsAt === undefined) return ms;
  const weeklyMs = Date.parse(weeklyResetsAt);
  return Math.abs(weeklyMs - ms) <= SNAP_MS ? weeklyMs : ms;
};

const formatDuration = (ms: number) => {
  if (ms <= 0) return "now";
  const totalMin = Math.floor(ms / 60000);
  const hours = Math.floor(totalMin / 60);
  if (hours >= 24) return `${Math.floor(hours / 24)}d ${hours % 24}h`;
  if (hours > 0) return `${hours}h ${totalMin % 60}m`;
  return `${totalMin}m`;
};

const pad = (n: number) => String(n).padStart(2, "0");

const formatLine = (r: Reading, nowMs: number, offsetMs: number) => {
  const usage = r.percent < 50 ? GREEN : r.percent < 80 ? YELLOW : RED;
  let line = `🦋 ${DIM}Fable${RESET} ${usage}${r.percent}%${RESET}`;
  if (r.resetsAtMs !== undefined) {
    const remaining = r.resetsAtMs - nowMs;
    const time = remaining < 30 * 60000
      ? RED
      : remaining < 60 * 60000
      ? YELLOW
      : GREEN;
    const d = new Date(r.resetsAtMs + offsetMs);
    const stamp = `${pad(d.getUTCMonth() + 1)}/${pad(d.getUTCDate())} ${
      pad(d.getUTCHours())
    }:${pad(d.getUTCMinutes())}`;
    line += ` ${time}${
      formatDuration(remaining)
    }${RESET} ${DIM}${stamp}${RESET}`;
  }
  return line;
};

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    const started = await next(e);
    if (!e.isInteractive) return started;

    const env = (await $.process.run(ENV_ARGV)).stdout.split("\n");
    const offsetMs = parseOffsetMs(env[0] ?? "");
    const lineFile = `${env[1]}/claude-fable-usage`;
    const readingFile = `${lineFile}.json`;
    const slotsDir = `${lineFile}.slots`;

    const claim = async () => {
      const slot = String(Math.floor((await $.clock.now()) / FETCH_MS));
      const argv = ["sh", "-c", CLAIM_SCRIPT, "sh", slotsDir, slot];
      return (await $.process.run(argv)).exitCode === 0;
    };
    const fetch = async () => {
      const { exitCode, stdout, stderr } = await $.process.run(USAGE_ARGV, {
        timeoutMs: 30_000,
      });
      if (exitCode !== 0) {
        $.ui.log(`fable-usage: /usage exited ${exitCode}: ${stderr}`, {
          to: "debug",
        });
        return;
      }
      const m = FABLE_LINE.exec(stdout);
      const parsed = m?.[2]
        ? parseResetMs(m[2], await $.clock.now(), offsetMs)
        : undefined;
      const weekly = (await $.session.usage()).rateLimits.find(
        (r) => r.kind === "seven_day",
      );
      const reading: Reading | null = m
        ? {
          percent: Number(m[1]),
          resetsAtMs: snapToWeekly(parsed, weekly?.resetsAt),
        }
        : null;
      await $.fs.write(readingFile, JSON.stringify(reading));
    };
    const render = async () => {
      const reading = JSON.parse(await $.fs.read(readingFile)) as
        | Reading
        | null;
      const text = reading
        ? formatLine(reading, await $.clock.now(), offsetMs)
        : "";
      await $.fs.write(lineFile, text);
    };
    const tick = async () => {
      if (await claim()) await fetch();
      await render();
    };
    const logged = () =>
      tick().catch((err) =>
        $.ui.log(`fable-usage: ${String(err)}`, { to: "debug" })
      );

    void logged();
    $.clock.every(RENDER_MS, logged);
    return started;
  });
};
