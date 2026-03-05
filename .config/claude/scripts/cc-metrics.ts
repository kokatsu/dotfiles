#!/usr/bin/env -S deno run --allow-read --allow-write=${CLAUDE_CONFIG_DIR},${HOME}/.claude,${HOME}/.config/claude --allow-env=HOME,CLAUDE_CONFIG_DIR

// ============================================================
// Types
// ============================================================

interface BaseEvent {
  ts: string;
  session: string;
}

interface SkillEvent extends BaseEvent {
  type: "user" | "auto";
  skill: string;
  args: string;
  cwd: string;
}

interface InstructionsEvent extends BaseEvent {
  file: string;
  type: string;
  reason: string;
  project: string;
}

type Subcommand = "dashboard" | "skills" | "instructions";

interface Args {
  subcommand: Subcommand;
  action: "show" | "prune";
  days: number;
  format: "text" | "json";
  yes: boolean;
  verbose: boolean;
}

// ============================================================
// Constants
// ============================================================

const CONFIG_DIR = Deno.env.get("CLAUDE_CONFIG_DIR") ||
  `${Deno.env.get("HOME")}/.claude`;
const SKILL_LOG = `${CONFIG_DIR}/skill-metrics.jsonl`;
const INSTRUCTIONS_LOG = `${CONFIG_DIR}/instructions-metrics.jsonl`;

// ============================================================
// Args
// ============================================================

function parseArgs(): Args {
  let subcommand: Subcommand = "dashboard";
  let action: Args["action"] = "show";
  let days = 30;
  let format: Args["format"] = "text";
  let yes = false;
  let verbose = false;

  for (let i = 0; i < Deno.args.length; i++) {
    switch (Deno.args[i]) {
      case "skills":
        subcommand = "skills";
        break;
      case "instructions":
        subcommand = "instructions";
        break;
      case "--prune":
        action = "prune";
        break;
      case "--days":
        days = parseInt(Deno.args[++i], 10);
        break;
      case "--json":
        format = "json";
        break;
      case "--yes":
      case "-y":
        yes = true;
        break;
      case "--verbose":
        verbose = true;
        break;
    }
  }

  return { subcommand, action, days, format, yes, verbose };
}

// ============================================================
// Common Utilities
// ============================================================

function localDateStr(d: Date = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function bar(count: number, max: number, width = 20): string {
  if (max <= 0) return "\u2591".repeat(width);
  const filled = Math.round((count / max) * width);
  return "\u2588".repeat(filled) + "\u2591".repeat(width - filled);
}

async function loadEvents<T extends BaseEvent>(
  path: string,
  days: number,
): Promise<T[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  try {
    const content = await Deno.readTextFile(path);
    const events: T[] = [];
    for (const line of content.trim().split("\n")) {
      if (!line.trim()) continue;
      try {
        const event: T = JSON.parse(line);
        if (new Date(event.ts) >= cutoff) events.push(event);
      } catch { /* skip malformed */ }
    }
    return events;
  } catch {
    return [];
  }
}

async function pruneLog(
  path: string,
  label: string,
  days: number,
  yes: boolean,
): Promise<void> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString();
  try {
    const content = await Deno.readTextFile(path);
    const lines = content.trimEnd().split("\n").filter((l) => l.trim());
    const kept = lines.filter((line) => {
      try {
        return (JSON.parse(line) as BaseEvent).ts >= cutoffStr;
      } catch {
        return false;
      }
    });
    const removed = lines.length - kept.length;
    if (removed > 0) {
      if (
        !yes && !confirm(
          `Prune ${removed} ${label} entries older than ${days} days? (${kept.length} remaining)`,
        )
      ) {
        console.log("Aborted.");
        return;
      }
      await Deno.writeTextFile(path, kept.join("\n") + "\n");
      console.log(
        `Pruned ${removed} entries. ${kept.length} remaining.`,
      );
    } else {
      console.log(
        `Nothing to prune. All ${kept.length} ${label} entries within ${days} days.`,
      );
    }
  } catch {
    console.log(`No ${label} log file found.`);
  }
}

function countByDay(events: BaseEvent[]): Map<string, number> {
  const byDay = new Map<string, number>();
  for (const e of events) {
    const day = localDateStr(new Date(e.ts));
    byDay.set(day, (byDay.get(day) || 0) + 1);
  }
  return byDay;
}

function countByWeek(events: BaseEvent[]): Map<string, number> {
  const byWeek = new Map<string, number>();
  for (const e of events) {
    const d = new Date(e.ts);
    const weekStart = new Date(d);
    // ISO week: Monday as first day (Sun=0 → offset 6, Mon=0 → offset 0, ...)
    weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    const weekKey = localDateStr(weekStart);
    byWeek.set(weekKey, (byWeek.get(weekKey) || 0) + 1);
  }
  return byWeek;
}

function renderDailyLines(
  byDay: Map<string, number>,
  days: number,
  maxWidth = 15,
): string[] {
  const trendDays = Math.min(14, days);
  const dailyData: Array<{ date: string; count: number }> = [];
  for (let i = trendDays - 1; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const dateStr = localDateStr(d);
    dailyData.push({ date: dateStr, count: byDay.get(dateStr) || 0 });
  }
  const maxDaily = Math.max(...dailyData.map((d) => d.count), 1);
  const maxDailyWidth = String(maxDaily).length;
  return dailyData.map((d) => {
    const label = d.date.slice(5);
    const b = d.count > 0
      ? bar(d.count, maxDaily, maxWidth)
      : "\u2591".repeat(maxWidth);
    return `  ${label}  ${b} ${String(d.count).padStart(maxDailyWidth)}`;
  });
}

function renderWeeklyLines(
  byWeek: Map<string, number>,
  maxWidth = 15,
): string[] {
  const weeklyData = [...byWeek.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-8);
  if (weeklyData.length <= 1) return [];
  const maxWeekly = Math.max(...weeklyData.map(([, c]) => c), 1);
  const maxWeeklyWidth = String(maxWeekly).length;
  return weeklyData.map(([weekStart, count]) => {
    const end = new Date(weekStart);
    end.setDate(end.getDate() + 6);
    const label = `${weekStart.slice(5)} ~ ${localDateStr(end).slice(5)}`;
    const b = bar(count, maxWeekly, maxWidth);
    return `  ${label}  ${b} ${String(count).padStart(maxWeeklyWidth)}`;
  });
}

function renderSessionStats(
  events: BaseEvent[],
  unit: string,
): string[] {
  const bySess = new Map<string, number>();
  for (const e of events) {
    bySess.set(e.session, (bySess.get(e.session) || 0) + 1);
  }
  const counts = [...bySess.values()];
  if (counts.length === 0) return [];
  const avg = (counts.reduce((a, b) => a + b, 0) / counts.length).toFixed(1);
  const max = Math.max(...counts);
  return [
    `  Sessions: ${counts.length}`,
    `  Avg: ${avg} ${unit}/session`,
    `  Max: ${max} ${unit}/session`,
  ];
}

function periodHeader(days: number): string[] {
  const now = new Date();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  return [
    `Period: ${localDateStr(cutoff)} ~ ${localDateStr(now)} (${days} days)`,
  ];
}

// ============================================================
// Aggregation Helpers
// ============================================================

interface SkillAgg {
  skill: string;
  total: number;
  user: number;
  auto: number;
}

function aggregateSkills(events: SkillEvent[]): SkillAgg[] {
  const bySkill = new Map<string, { user: number; auto: number }>();
  for (const e of events) {
    const entry = bySkill.get(e.skill) || { user: 0, auto: 0 };
    entry[e.type]++;
    bySkill.set(e.skill, entry);
  }
  return [...bySkill.entries()]
    .map(([skill, counts]) => ({
      skill,
      total: counts.user + counts.auto,
      ...counts,
    }))
    .sort((a, b) => b.total - a.total);
}

interface FileAgg {
  file: string;
  total: number;
  counts: Map<string, number>;
}

function aggregateFiles(events: InstructionsEvent[]): FileAgg[] {
  const byFile = new Map<string, Map<string, number>>();
  for (const e of events) {
    const entry = byFile.get(e.file) || new Map<string, number>();
    entry.set(e.type, (entry.get(e.type) || 0) + 1);
    byFile.set(e.file, entry);
  }
  return [...byFile.entries()]
    .map(([file, counts]) => ({
      file,
      total: [...counts.values()].reduce((a, b) => a + b, 0),
      counts,
    }))
    .sort((a, b) => b.total - a.total);
}

// ============================================================
// Skill Metrics (detailed)
// ============================================================

function generateSkillMetrics(events: SkillEvent[], days: number): string {
  if (events.length === 0) {
    return "No data yet. Skill invocations will be recorded as you use them.";
  }

  const lines: string[] = [];

  const userCount = events.filter((e) => e.type === "user").length;
  const autoCount = events.filter((e) => e.type === "auto").length;
  const total = events.length;
  const userPct = ((userCount / total) * 100).toFixed(1);
  const autoPct = ((autoCount / total) * 100).toFixed(1);

  lines.push("# Skill Metrics");
  lines.push("");
  lines.push(...periodHeader(days));
  lines.push("");
  lines.push("## Summary");
  lines.push(`Total: ${total}`);
  lines.push(`  User (/command): ${userCount} (${userPct}%)`);
  lines.push(`  Auto (trigger):  ${autoCount} (${autoPct}%)`);
  lines.push("");

  // Ranking
  const sorted = aggregateSkills(events);
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

  // Daily
  lines.push(`## Daily (last ${Math.min(14, days)} days)`);
  lines.push(...renderDailyLines(countByDay(events), days));
  lines.push("");

  // Weekly
  const weeklyLines = renderWeeklyLines(countByWeek(events));
  if (weeklyLines.length > 0) {
    lines.push("## Weekly");
    lines.push(...weeklyLines);
    lines.push("");
  }

  // Session Stats
  lines.push("## Session Stats");
  lines.push(...renderSessionStats(events, "skills"));
  lines.push("");

  // Duration Correlation
  const bySess = new Map<string, SkillEvent[]>();
  for (const e of events) {
    const list = bySess.get(e.session) || [];
    list.push(e);
    bySess.set(e.session, list);
  }

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
    const maxSessionCountWidth = String(
      Math.max(...durationRows.map(([, d]) => d.length)),
    ).length;
    for (const [label, data] of durationRows) {
      lines.push(
        `  ${label.padEnd(maxLabelLen)}: ${
          String(data.length).padStart(maxSessionCountWidth)
        } sessions, avg ${avg(data)} skills/session`,
      );
    }
    lines.push("");
  }

  // Breakdown
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

// ============================================================
// Instructions Metrics (detailed)
// ============================================================

function generateInstructionsMetrics(
  events: InstructionsEvent[],
  days: number,
): string {
  if (events.length === 0) {
    return "No data yet. Instructions load events will be recorded as sessions start.";
  }

  const lines: string[] = [];
  const total = events.length;
  const byType = new Map<string, number>();
  for (const e of events) {
    byType.set(e.type, (byType.get(e.type) || 0) + 1);
  }

  lines.push("# Instructions Metrics");
  lines.push("");
  lines.push(...periodHeader(days));
  lines.push("");
  lines.push("## Summary");
  lines.push(`Total: ${total}`);
  const typeSorted = [...byType.entries()].sort(([, a], [, b]) => b - a);
  const maxTypeLen = Math.max(...typeSorted.map(([k]) => k.length));
  const maxTypeCountWidth = String(
    Math.max(...typeSorted.map(([, v]) => v)),
  ).length;
  for (const [type, count] of typeSorted) {
    const pct = ((count / total) * 100).toFixed(1);
    lines.push(
      `  ${type.padEnd(maxTypeLen)}: ${
        String(count).padStart(maxTypeCountWidth)
      } (${pct}%)`,
    );
  }
  lines.push("");

  // File Ranking
  const fileSorted = aggregateFiles(events);
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

  // Project Ranking
  const byProject = new Map<string, number>();
  for (const e of events) {
    byProject.set(e.project, (byProject.get(e.project) || 0) + 1);
  }

  const projectSorted = [...byProject.entries()].sort(
    ([, a], [, b]) => b - a,
  );

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

  // Daily
  lines.push(`## Daily (last ${Math.min(14, days)} days)`);
  lines.push(...renderDailyLines(countByDay(events), days));
  lines.push("");

  // Weekly
  const weeklyLines = renderWeeklyLines(countByWeek(events));
  if (weeklyLines.length > 0) {
    lines.push("## Weekly");
    lines.push(...weeklyLines);
    lines.push("");
  }

  // Session Stats
  lines.push("## Session Stats");
  lines.push(...renderSessionStats(events, "files"));
  lines.push("");

  // Breakdown
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
        const width = Math.max(
          1,
          Math.round((count / maxBreakdownCount) * 30),
        );
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

// ============================================================
// Dashboard (combined overview)
// ============================================================

function generateDashboard(
  skillEvents: SkillEvent[],
  instrEvents: InstructionsEvent[],
  days: number,
): string {
  const lines: string[] = [];

  lines.push("# Claude Code Metrics");
  lines.push("");
  lines.push(...periodHeader(days));
  lines.push("");

  // Skills Summary + Top 5
  if (skillEvents.length > 0) {
    const userCount = skillEvents.filter((e) => e.type === "user").length;
    const autoCount = skillEvents.filter((e) => e.type === "auto").length;
    lines.push(
      `## Skills: ${skillEvents.length} total (user: ${userCount}, auto: ${autoCount})`,
    );

    const sorted = aggregateSkills(skillEvents).slice(0, 5);
    const maxCount = sorted[0]?.total || 1;
    const maxNameLen = Math.max(...sorted.map((s) => s.skill.length));
    const maxCountWidth = String(maxCount).length;
    for (let i = 0; i < sorted.length; i++) {
      const s = sorted[i];
      const rank = `${i + 1}.`.padEnd(3);
      const name = s.skill.padEnd(maxNameLen);
      const b = bar(s.total, maxCount, 15);
      lines.push(
        `  ${rank} ${name} ${b} ${
          String(s.total).padStart(maxCountWidth)
        }  (user: ${s.user}, auto: ${s.auto})`,
      );
    }
  } else {
    lines.push("## Skills: No data");
  }
  lines.push("");

  // Instructions Summary + Top 5
  if (instrEvents.length > 0) {
    const byType = new Map<string, number>();
    for (const e of instrEvents) {
      byType.set(e.type, (byType.get(e.type) || 0) + 1);
    }
    const typeSummary = [...byType.entries()]
      .sort(([, a], [, b]) => b - a)
      .map(([t, c]) => `${t}: ${c}`)
      .join(", ");
    lines.push(
      `## Instructions: ${instrEvents.length} total (${typeSummary})`,
    );

    const sorted = aggregateFiles(instrEvents).slice(0, 5);
    const maxCount = sorted[0]?.total || 1;
    const maxFileLen = Math.max(...sorted.map((s) => s.file.length));
    const maxCountWidth = String(maxCount).length;
    for (let i = 0; i < sorted.length; i++) {
      const s = sorted[i];
      const rank = `${i + 1}.`.padEnd(3);
      const name = s.file.padEnd(maxFileLen);
      const b = bar(s.total, maxCount, 15);
      lines.push(
        `  ${rank} ${name} ${b} ${String(s.total).padStart(maxCountWidth)}`,
      );
    }
  } else {
    lines.push("## Instructions: No data");
  }
  lines.push("");

  // Combined Daily Trend
  const allEvents: BaseEvent[] = [...skillEvents, ...instrEvents];
  if (allEvents.length > 0) {
    const skillByDay = countByDay(skillEvents);
    const instrByDay = countByDay(instrEvents);
    const allByDay = countByDay(allEvents);

    const trendDays = Math.min(14, days);
    const dailyData: Array<{
      date: string;
      total: number;
      skills: number;
      instr: number;
    }> = [];
    for (let i = trendDays - 1; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const dateStr = localDateStr(d);
      dailyData.push({
        date: dateStr,
        total: allByDay.get(dateStr) || 0,
        skills: skillByDay.get(dateStr) || 0,
        instr: instrByDay.get(dateStr) || 0,
      });
    }

    const maxDaily = Math.max(...dailyData.map((d) => d.total), 1);
    const maxDailyWidth = String(maxDaily).length;

    lines.push(`## Daily (last ${trendDays} days)`);
    for (const d of dailyData) {
      const label = d.date.slice(5);
      const b = d.total > 0 ? bar(d.total, maxDaily, 15) : "\u2591".repeat(15);
      lines.push(
        `  ${label}  ${b} ${
          String(d.total).padStart(maxDailyWidth)
        }  (skills: ${d.skills}, instr: ${d.instr})`,
      );
    }
    lines.push("");
  }

  return lines.join("\n");
}

// ============================================================
// JSON Output
// ============================================================

function skillJson(
  events: SkillEvent[],
  days: number,
  verbose: boolean,
): Record<string, unknown> {
  const from = localDateStr(new Date(Date.now() - days * 86400000));
  const to = localDateStr();

  const bySkill: Record<string, { user: number; auto: number }> = {};
  for (const e of events) {
    if (!bySkill[e.skill]) bySkill[e.skill] = { user: 0, auto: 0 };
    bySkill[e.skill][e.type]++;
  }

  const result: Record<string, unknown> = {
    period: { days, from, to },
    total: events.length,
    byType: {
      user: events.filter((e) => e.type === "user").length,
      auto: events.filter((e) => e.type === "auto").length,
    },
    bySkill,
  };
  if (verbose) result.events = events;
  return result;
}

function instructionsJson(
  events: InstructionsEvent[],
  days: number,
  verbose: boolean,
): Record<string, unknown> {
  const from = localDateStr(new Date(Date.now() - days * 86400000));
  const to = localDateStr();

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

  const result: Record<string, unknown> = {
    period: { days, from, to },
    total: events.length,
    byType: byTypeJson,
    byFile,
    byProject,
  };
  if (verbose) result.events = events;
  return result;
}

function dashboardJson(
  skills: SkillEvent[],
  instr: InstructionsEvent[],
  days: number,
  verbose: boolean,
): Record<string, unknown> {
  const from = localDateStr(new Date(Date.now() - days * 86400000));
  const to = localDateStr();

  const bySkill: Record<string, { user: number; auto: number }> = {};
  for (const e of skills) {
    if (!bySkill[e.skill]) bySkill[e.skill] = { user: 0, auto: 0 };
    bySkill[e.skill][e.type]++;
  }

  const byFile: Record<string, Record<string, number>> = {};
  for (const e of instr) {
    if (!byFile[e.file]) byFile[e.file] = {};
    byFile[e.file][e.type] = (byFile[e.file][e.type] || 0) + 1;
  }

  const result: Record<string, unknown> = {
    period: { days, from, to },
    skills: {
      total: skills.length,
      byType: {
        user: skills.filter((e) => e.type === "user").length,
        auto: skills.filter((e) => e.type === "auto").length,
      },
      bySkill,
    },
    instructions: {
      total: instr.length,
      byFile,
    },
  };
  if (verbose) {
    result.skillEvents = skills;
    result.instructionEvents = instr;
  }
  return result;
}

// ============================================================
// Main
// ============================================================

async function main() {
  const { subcommand, action, days, format, yes, verbose } = parseArgs();

  if (action === "prune") {
    if (subcommand === "dashboard" || subcommand === "skills") {
      await pruneLog(SKILL_LOG, "skill", days, yes);
    }
    if (subcommand === "dashboard" || subcommand === "instructions") {
      await pruneLog(INSTRUCTIONS_LOG, "instructions", days, yes);
    }
    return;
  }

  if (subcommand === "skills") {
    const events = await loadEvents<SkillEvent>(SKILL_LOG, days);
    if (format === "json") {
      console.log(JSON.stringify(skillJson(events, days, verbose), null, 2));
    } else {
      console.log(generateSkillMetrics(events, days));
    }
  } else if (subcommand === "instructions") {
    const events = await loadEvents<InstructionsEvent>(INSTRUCTIONS_LOG, days);
    if (format === "json") {
      console.log(
        JSON.stringify(instructionsJson(events, days, verbose), null, 2),
      );
    } else {
      console.log(generateInstructionsMetrics(events, days));
    }
  } else {
    const [skills, instr] = await Promise.all([
      loadEvents<SkillEvent>(SKILL_LOG, days),
      loadEvents<InstructionsEvent>(INSTRUCTIONS_LOG, days),
    ]);
    if (format === "json") {
      console.log(
        JSON.stringify(dashboardJson(skills, instr, days, verbose), null, 2),
      );
    } else {
      console.log(generateDashboard(skills, instr, days));
    }
  }
}

main();
