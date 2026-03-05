#!/usr/bin/env -S deno run --allow-read --allow-write=${CLAUDE_CONFIG_DIR},${HOME}/.claude,${HOME}/.config/claude --allow-env=HOME,CLAUDE_CONFIG_DIR

interface InstructionsEvent {
  ts: string;
  file: string;
  type: string;
  reason: string;
  session: string;
  project: string;
}

const CONFIG_DIR = Deno.env.get("CLAUDE_CONFIG_DIR") ||
  `${Deno.env.get("HOME")}/.claude`;
const LOG_PATH = `${CONFIG_DIR}/instructions-metrics.jsonl`;

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

async function loadEvents(days: number): Promise<InstructionsEvent[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  try {
    const content = await Deno.readTextFile(LOG_PATH);
    const events: InstructionsEvent[] = [];
    for (const line of content.trim().split("\n")) {
      if (!line.trim()) continue;
      try {
        const event: InstructionsEvent = JSON.parse(line);
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

function generateMetrics(events: InstructionsEvent[], days: number): string {
  if (events.length === 0) {
    return "No data yet. Instructions load events will be recorded as sessions start.";
  }

  const lines: string[] = [];
  const now = new Date();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  // --- Summary ---
  const total = events.length;
  const byType = new Map<string, number>();
  for (const e of events) {
    byType.set(e.type, (byType.get(e.type) || 0) + 1);
  }

  lines.push("# Instructions Metrics");
  lines.push("");
  lines.push(
    `Period: ${cutoff.toISOString().split("T")[0]} ~ ${
      now.toISOString().split("T")[0]
    } (${days} days)`,
  );
  lines.push("");
  lines.push("## Summary");
  lines.push(`Total: ${total}`);
  const typeSorted = [...byType.entries()].sort(([, a], [, b]) => b - a);
  const maxTypeLen = Math.max(...typeSorted.map(([k]) => k.length));
  const maxTypeCountWidth =
    String(Math.max(...typeSorted.map(([, v]) => v))).length;
  for (const [type, count] of typeSorted) {
    const pct = ((count / total) * 100).toFixed(1);
    lines.push(
      `  ${type.padEnd(maxTypeLen)}: ${
        String(count).padStart(maxTypeCountWidth)
      } (${pct}%)`,
    );
  }
  lines.push("");

  // --- File Ranking ---
  const byFile = new Map<string, Map<string, number>>();
  for (const e of events) {
    const entry = byFile.get(e.file) || new Map<string, number>();
    entry.set(e.type, (entry.get(e.type) || 0) + 1);
    byFile.set(e.file, entry);
  }

  const fileSorted = [...byFile.entries()]
    .map(([file, counts]) => ({
      file,
      total: [...counts.values()].reduce((a, b) => a + b, 0),
      counts,
    }))
    .sort((a, b) => b.total - a.total);

  const maxFileCount = fileSorted[0]?.total || 1;
  const maxFileLen = Math.max(...fileSorted.map((s) => s.file.length));
  const maxCountWidth = String(maxFileCount).length;
  const maxRankWidth = String(fileSorted.length).length + 1;

  lines.push("## File Ranking");
  for (let i = 0; i < fileSorted.length; i++) {
    const s = fileSorted[i];
    const rank = `${i + 1}.`.padEnd(maxRankWidth + 1);
    const name = s.file.padEnd(maxFileLen);
    const b = bar(s.total, maxFileCount, 15);
    lines.push(
      `  ${rank} ${name} ${b} ${String(s.total).padStart(maxCountWidth)}`,
    );
  }
  lines.push("");

  // --- Project Ranking ---
  const byProject = new Map<string, number>();
  for (const e of events) {
    byProject.set(e.project, (byProject.get(e.project) || 0) + 1);
  }

  const projectSorted = [...byProject.entries()]
    .sort(([, a], [, b]) => b - a);

  const maxProjectCount = projectSorted[0]?.[1] || 1;
  const maxProjectLen = Math.max(...projectSorted.map(([p]) => p.length));
  const maxProjectCountWidth = String(maxProjectCount).length;
  const maxProjectRankWidth = String(projectSorted.length).length + 1;

  lines.push("## Project Ranking");
  for (let i = 0; i < projectSorted.length; i++) {
    const [project, count] = projectSorted[i];
    const rank = `${i + 1}.`.padEnd(maxProjectRankWidth + 1);
    const name = project.padEnd(maxProjectLen);
    const b = bar(count, maxProjectCount, 15);
    lines.push(
      `  ${rank} ${name} ${b} ${String(count).padStart(maxProjectCountWidth)}`,
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
    weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7));
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
  const bySess = new Map<string, InstructionsEvent[]>();
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
  lines.push(`  Avg: ${avgPerSession} files/session`);
  lines.push(`  Max: ${maxPerSession} files/session`);
  lines.push("");

  // --- Type Breakdown ---
  const typeSymbols: Record<string, string> = {
    User: "\u25cf",
    Project: "\u25cb",
    Local: "\u25d2",
  };
  const defaultSymbol = "\u25c6";

  const maxBreakdownCount = Math.max(...fileSorted.map((s) => s.total), 1);

  lines.push("## Breakdown");
  for (const s of fileSorted) {
    const dots = [...s.counts.entries()]
      .map(([type, count]) => {
        const sym = typeSymbols[type] || defaultSymbol;
        const width = Math.max(1, Math.round((count / maxBreakdownCount) * 30));
        return sym.repeat(width);
      })
      .join("");
    lines.push(`  ${s.file.padEnd(maxFileLen)} ${dots}`);
  }
  const legend = [...byType.keys()]
    .map((t) => `${typeSymbols[t] || defaultSymbol} = ${t}`)
    .join(", ");
  lines.push(`  ${"".padEnd(maxFileLen)} ${legend}`);
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
        return (JSON.parse(line) as InstructionsEvent).ts >= cutoffStr;
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
    const byFile: Record<string, Record<string, number>> = {};
    for (const e of events) {
      if (!byFile[e.file]) byFile[e.file] = {};
      byFile[e.file][e.type] = (byFile[e.file][e.type] || 0) + 1;
    }

    const byTypeJson: Record<string, number> = {};
    for (const e of events) {
      byTypeJson[e.type] = (byTypeJson[e.type] || 0) + 1;
    }

    const byProject: Record<string, number> = {};
    for (const e of events) {
      byProject[e.project] = (byProject[e.project] || 0) + 1;
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
      byType: byTypeJson,
      byFile,
      byProject,
      events,
    };
    console.log(JSON.stringify(output, null, 2));
  } else {
    console.log(generateMetrics(events, days));
  }
}

main();
