#!/usr/bin/env -S deno run --allow-read --allow-write=${CLAUDE_CONFIG_DIR},${HOME}/.claude,${HOME}/.config/claude --allow-env=HOME,CLAUDE_CONFIG_DIR

interface SkillEvent {
  ts: string;
  type: "user" | "auto";
  skill: string;
  session: string;
  args: string;
  cwd: string;
}

const CONFIG_DIR = Deno.env.get("CLAUDE_CONFIG_DIR") ||
  `${Deno.env.get("HOME")}/.claude`;
const LOG_PATH = `${CONFIG_DIR}/skill-metrics.jsonl`;

interface Args {
  action: "show" | "prune";
  days: number;
  format: "text" | "json";
}

function parseArgs(): Args {
  let action: Args["action"] = "show";
  let days = 30;
  let format: Args["format"] = "text";

  for (let i = 0; i < Deno.args.length; i++) {
    switch (Deno.args[i]) {
      case "--prune":
        action = "prune";
        break;
      case "--days":
        days = parseInt(Deno.args[++i], 10);
        break;
      case "--json":
        format = "json";
        break;
    }
  }

  return { action, days, format };
}

async function loadEvents(days: number): Promise<SkillEvent[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  try {
    const content = await Deno.readTextFile(LOG_PATH);
    const events: SkillEvent[] = [];
    for (const line of content.trim().split("\n")) {
      if (!line.trim()) continue;
      try {
        const event: SkillEvent = JSON.parse(line);
        if (new Date(event.ts) >= cutoff) {
          events.push(event);
        }
      } catch {
        // skip malformed lines
      }
    }
    return events;
  } catch {
    return [];
  }
}

function bar(count: number, max: number, width = 20): string {
  const filled = Math.round((count / max) * width);
  return "\u2588".repeat(filled) + "\u2591".repeat(width - filled);
}

function generateMetrics(events: SkillEvent[], days: number): string {
  if (events.length === 0) {
    return "No data yet. Skill invocations will be recorded as you use them.";
  }

  const lines: string[] = [];
  const now = new Date();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  // --- Summary ---
  const userCount = events.filter((e) => e.type === "user").length;
  const autoCount = events.filter((e) => e.type === "auto").length;
  const total = events.length;
  const userPct = ((userCount / total) * 100).toFixed(1);
  const autoPct = ((autoCount / total) * 100).toFixed(1);

  lines.push("# Skill Metrics");
  lines.push("");
  lines.push(
    `Period: ${cutoff.toISOString().split("T")[0]} ~ ${
      now.toISOString().split("T")[0]
    } (${days} days)`,
  );
  lines.push("");
  lines.push("## Summary");
  lines.push(`Total: ${total}`);
  lines.push(`  User (/command): ${userCount} (${userPct}%)`);
  lines.push(`  Auto (trigger):  ${autoCount} (${autoPct}%)`);
  lines.push("");

  // --- By Skill Ranking ---
  const bySkill = new Map<string, { user: number; auto: number }>();
  for (const e of events) {
    const entry = bySkill.get(e.skill) || { user: 0, auto: 0 };
    entry[e.type]++;
    bySkill.set(e.skill, entry);
  }

  const sorted = [...bySkill.entries()]
    .map(([skill, counts]) => ({
      skill,
      total: counts.user + counts.auto,
      ...counts,
    }))
    .sort((a, b) => b.total - a.total);

  const maxCount = sorted[0]?.total || 1;
  const maxNameLen = Math.max(...sorted.map((s) => s.skill.length));
  const maxCountWidth = String(maxCount).length;
  const maxRankWidth = String(sorted.length).length + 1;

  lines.push("## Ranking");
  for (let i = 0; i < sorted.length; i++) {
    const s = sorted[i];
    const rank = `${i + 1}.`.padEnd(maxRankWidth + 1);
    const name = s.skill.padEnd(maxNameLen);
    const b = bar(s.total, maxCount, 15);
    lines.push(
      `  ${rank} ${name} ${b} ${
        String(s.total).padStart(maxCountWidth)
      }  (user: ${s.user}, auto: ${s.auto})`,
    );
  }
  lines.push("");

  // --- Daily Trend (last 14 days) ---
  const byDay = new Map<string, number>();
  for (const e of events) {
    const day = e.ts.split("T")[0];
    byDay.set(day, (byDay.get(day) || 0) + 1);
  }

  const trendDays = Math.min(14, days);
  const dailyData: Array<{ date: string; count: number }> = [];
  for (let i = trendDays - 1; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const dateStr = d.toISOString().split("T")[0];
    dailyData.push({ date: dateStr, count: byDay.get(dateStr) || 0 });
  }

  const maxDaily = Math.max(...dailyData.map((d) => d.count), 1);

  const maxDailyWidth = String(maxDaily).length;

  lines.push(`## Daily (last ${trendDays} days)`);
  for (const d of dailyData) {
    const label = d.date.slice(5);
    const b = d.count > 0 ? bar(d.count, maxDaily, 15) : "\u2591".repeat(15);
    lines.push(`  ${label}  ${b} ${String(d.count).padStart(maxDailyWidth)}`);
  }
  lines.push("");

  // --- Weekly Trend ---
  const byWeek = new Map<string, number>();
  for (const e of events) {
    const d = new Date(e.ts);
    const weekStart = new Date(d);
    weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // Monday
    const weekKey = weekStart.toISOString().split("T")[0];
    byWeek.set(weekKey, (byWeek.get(weekKey) || 0) + 1);
  }

  const weeklyData = [...byWeek.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-8);

  if (weeklyData.length > 1) {
    const maxWeekly = Math.max(...weeklyData.map(([, c]) => c), 1);
    const maxWeeklyWidth = String(maxWeekly).length;

    lines.push("## Weekly");
    for (const [weekStart, count] of weeklyData) {
      const end = new Date(weekStart);
      end.setDate(end.getDate() + 6);
      const label = `${weekStart.slice(5)} ~ ${
        end.toISOString().split("T")[0].slice(5)
      }`;
      const b = bar(count, maxWeekly, 15);
      lines.push(`  ${label}  ${b} ${String(count).padStart(maxWeeklyWidth)}`);
    }
    lines.push("");
  }

  // --- Session Stats ---
  const bySess = new Map<string, SkillEvent[]>();
  for (const e of events) {
    const list = bySess.get(e.session) || [];
    list.push(e);
    bySess.set(e.session, list);
  }

  const sessionCounts = [...bySess.values()].map((evts) => evts.length);
  const avgPerSession = (
    sessionCounts.reduce((a, b) => a + b, 0) / sessionCounts.length
  ).toFixed(1);
  const maxPerSession = Math.max(...sessionCounts);

  lines.push("## Session Stats");
  lines.push(`  Sessions: ${sessionCounts.length}`);
  lines.push(`  Avg: ${avgPerSession} skills/session`);
  lines.push(`  Max: ${maxPerSession} skills/session`);
  lines.push("");

  // --- Session Duration Correlation ---
  const sessionDurations: Array<{ duration: number; count: number }> = [];
  for (const [, evts] of bySess) {
    if (evts.length < 1) continue;
    const timestamps = evts.map((e) => new Date(e.ts).getTime()).sort();
    const durationMin = (timestamps[timestamps.length - 1] - timestamps[0]) /
      60000;
    sessionDurations.push({ duration: durationMin, count: evts.length });
  }

  if (sessionDurations.length >= 3) {
    const short = sessionDurations.filter((s) => s.duration < 10);
    const medium = sessionDurations.filter(
      (s) => s.duration >= 10 && s.duration < 30,
    );
    const long = sessionDurations.filter((s) => s.duration >= 30);

    const avg = (arr: typeof sessionDurations) =>
      arr.length > 0
        ? (arr.reduce((sum, s) => sum + s.count, 0) / arr.length).toFixed(1)
        : "-";

    lines.push("## Duration Correlation");
    const durationRows: Array<[string, typeof short]> = [
      ["Short  (<10min)", short],
      ["Medium (10-30min)", medium],
      ["Long   (>30min)", long],
    ];
    const maxLabelLen = Math.max(...durationRows.map(([l]) => l.length));
    const maxSessionCountWidth = String(Math.max(...durationRows.map(([, d]) =>
      d.length
    ))).length;
    for (const [label, data] of durationRows) {
      lines.push(
        `  ${label.padEnd(maxLabelLen)}: ${
          String(data.length).padStart(maxSessionCountWidth)
        } sessions, avg ${avg(data)} skills/session`,
      );
    }
    lines.push("");
  }

  // --- User/Auto breakdown per skill ---
  const maxBreakdownCount = Math.max(...sorted.map((s) => s.total), 1);

  lines.push("## Breakdown");
  for (const s of sorted) {
    const userWidth = s.user > 0
      ? Math.max(1, Math.round((s.user / maxBreakdownCount) * 30))
      : 0;
    const autoWidth = s.auto > 0
      ? Math.max(1, Math.round((s.auto / maxBreakdownCount) * 30))
      : 0;
    const userDots = "\u25cf".repeat(userWidth);
    const autoDots = "\u25cb".repeat(autoWidth);
    lines.push(
      `  ${s.skill.padEnd(maxNameLen)} ${userDots}${autoDots}`,
    );
  }
  lines.push(`  ${"".padEnd(maxNameLen)} \u25cf = user, \u25cb = auto`);
  lines.push("");

  return lines.join("\n");
}

async function pruneEntries(days: number): Promise<void> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString();

  try {
    const content = await Deno.readTextFile(LOG_PATH);
    const lines = content.trimEnd().split("\n").filter((l) => l.trim());
    const kept = lines.filter((line) => {
      try {
        return (JSON.parse(line) as SkillEvent).ts >= cutoffStr;
      } catch {
        return false;
      }
    });

    const removed = lines.length - kept.length;
    if (removed > 0) {
      if (
        !confirm(
          `Prune ${removed} entries older than ${days} days? (${kept.length} remaining)`,
        )
      ) {
        console.log("Aborted.");
        return;
      }
      await Deno.writeTextFile(LOG_PATH, kept.join("\n") + "\n");
      console.log(
        `Pruned ${removed} entries. ${kept.length} entries remaining.`,
      );
    } else {
      console.log(
        `Nothing to prune. All ${kept.length} entries are within ${days} days.`,
      );
    }
  } catch {
    console.log("No log file found.");
  }
}

async function main() {
  const { action, days, format } = parseArgs();

  if (action === "prune") {
    await pruneEntries(days);
    return;
  }

  const events = await loadEvents(days);

  if (format === "json") {
    const bySkill: Record<string, { user: number; auto: number }> = {};
    for (const e of events) {
      if (!bySkill[e.skill]) bySkill[e.skill] = { user: 0, auto: 0 };
      bySkill[e.skill][e.type]++;
    }

    const output = {
      period: {
        days,
        from: new Date(Date.now() - days * 86400000)
          .toISOString()
          .split("T")[0],
        to: new Date().toISOString().split("T")[0],
      },
      total: events.length,
      byType: {
        user: events.filter((e) => e.type === "user").length,
        auto: events.filter((e) => e.type === "auto").length,
      },
      bySkill,
      events,
    };
    console.log(JSON.stringify(output, null, 2));
  } else {
    console.log(generateMetrics(events, days));
  }
}

main();
