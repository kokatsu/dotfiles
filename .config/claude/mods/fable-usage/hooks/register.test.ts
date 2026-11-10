import { expect, mock, test } from "claude-code/testing";
import type { On } from "claude-code";

const NOW = Date.UTC(2026, 10, 10, 6, 0); // 2026-11-10 15:00 +0900
const WEEKLY_RESET = "2026-11-16T23:00:00.000Z"; // 11/17 08:00 +0900
const FABLE_7_59 =
  "Current week (Fable): 2% used · resets Nov 17, 7:59am (Asia/Tokyo)\n";
const LINE_FILE = "/cache/claude-fable-usage";
const READING_FILE = `${LINE_FILE}.json`;
const MINUTE = 60 * 1000;
// deno-lint-ignore no-control-regex
const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "");

type File = { text: string; mtimeMs: number };

const result = (exitCode: number, stdout: string) => ({
  value: {
    exitCode,
    stdout,
    stderr: "",
    isStdoutTruncated: false,
    isStderrTruncated: false,
  },
});

const world = (
  on: On,
  usageStdout: string,
  { now = NOW, files = new Map<string, File>(), usageExit = 0 } = {},
) => {
  const clock = mock.clock(on, { now });
  const claimed = new Set<string>();
  let usageRuns = 0;
  on("session.start", (_$, e) => ({ cwd: e.cwd }));
  on("process.run", (_$, e) => {
    if (e.argv[0] === "sh" && e.argv.length > 3) {
      const slot = e.argv.at(-1) ?? "";
      if (claimed.has(slot)) return result(1, "");
      claimed.add(slot);
      return result(0, "");
    }
    if (e.argv[0] === "sh") return result(0, "+0900\n/cache");
    usageRuns += 1;
    return result(usageExit, usageExit === 0 ? usageStdout : "");
  });
  on("session.usage", () => ({
    value: {
      startedAt: 0,
      context: { window: 1_000_000 },
      rateLimits: [{
        kind: "seven_day",
        percentUsed: 2,
        resetsAt: WEEKLY_RESET,
      }],
    },
  }));
  on("fs.write", (_$, e) => {
    files.set(e.path, { text: e.text, mtimeMs: clock.now() });
    return { value: undefined };
  });
  on("fs.read", (_$, e) => {
    const file = files.get(e.path);
    return file ? { value: file.text } : { deny: `ENOENT: ${e.path}` };
  });
  on("fs.stat", (_$, e) => {
    const file = files.get(e.path);
    return file
      ? {
        value: {
          kind: "file",
          size: file.text.length,
          mtimeMs: file.mtimeMs,
          isLink: false,
        },
      }
      : { deny: `ENOENT: ${e.path}` };
  });
  const line = () => strip(files.get(LINE_FILE)?.text ?? "");
  return { clock, files, line, usageRuns: () => usageRuns };
};

const interactive = {
  cwd: "/w",
  surface: "terminal",
  isInteractive: true,
} as const;

test(
  "writes the Fable line, snapped to the weekly reset, and re-renders it",
  async ($, on) => {
    const { clock, line } = world(on, FABLE_7_59);
    await $.session.start(interactive);
    await clock.settle();
    expect(line()).toBe("🦋 2% 6d 17h 11/17 08:00");

    await clock.advance(60 * MINUTE);
    expect(line()).toBe("🦋 2% 6d 16h 11/17 08:00");
  },
);

test("clears the line when /usage has no Fable window", async ($, on) => {
  const { clock, files } = world(on, "Current week (all models): 2% used\n");
  await $.session.start(interactive);
  await clock.settle();
  expect(files.get(LINE_FILE)?.text).toBe("");
});

test("a headless session runs nothing", async ($, on) => {
  const { clock, files, usageRuns } = world(on, FABLE_7_59);
  await $.session.start({ cwd: "/w", surface: null, isInteractive: false });
  await clock.settle();
  expect(usageRuns()).toBe(0);
  expect(files.size).toBe(0);
});

test("reads a reset that falls in the next year", async ($, on) => {
  const { clock, line } = world(
    on,
    "Current week (Fable): 2% used · resets Jan 1, 2027, 8am (Asia/Tokyo)\n",
    { now: Date.UTC(2026, 11, 28, 6, 0) }, // 2026-12-28 15:00 +0900
  );
  await $.session.start(interactive);
  await clock.settle();
  expect(line()).toBe("🦋 2% 3d 17h 01/01 08:00");
});

test(
  "a session started later renders the reading without running /usage",
  async ($, on) => {
    const { clock, files, line, usageRuns } = world(on, FABLE_7_59);
    await $.session.start(interactive);
    await clock.settle();
    files.set(READING_FILE, {
      text: JSON.stringify({
        percent: 40,
        resetsAtMs: Date.parse(WEEKLY_RESET),
      }),
      mtimeMs: clock.now(),
    });
    await clock.advance(2 * MINUTE);
    await $.session.start(interactive);
    await clock.settle();
    expect(usageRuns()).toBe(1);
    expect(line()).toBe("🦋 40% 6d 16h 11/17 08:00");
  },
);

test(
  "runs /usage once per five minutes, not once per minute",
  async ($, on) => {
    const { clock, usageRuns } = world(on, FABLE_7_59);
    await $.session.start(interactive);
    await clock.settle();
    await clock.advance(14 * MINUTE);
    expect(usageRuns()).toBe(3);
  },
);

test(
  "a failed /usage keeps the last reading and waits for the next slot",
  async ($, on) => {
    const files = new Map<string, File>([[READING_FILE, {
      text: JSON.stringify({
        percent: 40,
        resetsAtMs: Date.parse(WEEKLY_RESET),
      }),
      mtimeMs: NOW - 10 * MINUTE,
    }]]);
    const { clock, line, usageRuns } = world(on, "", { files, usageExit: 1 });
    await $.session.start(interactive);
    await clock.settle();
    expect(usageRuns()).toBe(1);
    expect(line()).toBe("🦋 40% 6d 17h 11/17 08:00");

    await clock.advance(MINUTE);
    expect(usageRuns()).toBe(1);
  },
);

test("sessions started together run /usage once", async ($, on) => {
  const { clock, line, usageRuns } = world(on, FABLE_7_59);
  await Promise.all([
    $.session.start(interactive),
    $.session.start(interactive),
  ]);
  await clock.settle();
  expect(usageRuns()).toBe(1);
  expect(line()).toBe("🦋 2% 6d 17h 11/17 08:00");

  await clock.advance(5 * MINUTE);
  expect(usageRuns()).toBe(2);
});
