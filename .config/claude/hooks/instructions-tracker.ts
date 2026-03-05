#!/usr/bin/env -S deno run --allow-read --allow-write=${CLAUDE_CONFIG_DIR},${HOME}/.claude,${HOME}/.config/claude --allow-env=HOME,CLAUDE_CONFIG_DIR

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  hook_event_name: string;
  file_path: string;
  memory_type: string;
  load_reason: string;
}

interface InstructionsEvent {
  ts: string;
  file: string;
  type: string;
  reason: string;
  session: string;
  project: string;
}

const HOME = Deno.env.get("HOME") || "";
const CONFIG_DIR = Deno.env.get("CLAUDE_CONFIG_DIR") ||
  `${HOME}/.claude`;
const LOG_PATH = `${CONFIG_DIR}/instructions-metrics.jsonl`;
const MAX_LOG_BYTES = 512 * 1024;

async function maybeRotate(path: string): Promise<void> {
  try {
    const stat = await Deno.stat(path);
    if (stat.size <= MAX_LOG_BYTES) return;

    const content = await Deno.readTextFile(path);
    const lines = content.trimEnd().split("\n");
    const kept = lines.slice(Math.floor(lines.length / 2));
    await Deno.writeTextFile(path, kept.join("\n") + "\n");
  } catch {
    // file doesn't exist or other error — ignore
  }
}

function shortenPath(filePath: string, cwd: string): string {
  const configDir = `${HOME}/.config/claude/`;
  const homeClaude = `${HOME}/.claude/`;

  if (filePath.startsWith(configDir)) {
    return `~claude/${filePath.slice(configDir.length)}`;
  }
  if (filePath.startsWith(homeClaude)) {
    return `~claude/${filePath.slice(homeClaude.length)}`;
  }
  const projectName = cwd.split("/").pop() || cwd;
  if (filePath.startsWith(cwd + "/")) {
    return `${projectName}/${filePath.slice(cwd.length + 1)}`;
  }
  const marker = `/${projectName}/`;
  const idx = filePath.lastIndexOf(marker);
  if (idx !== -1) {
    return `${projectName}/${filePath.slice(idx + marker.length)}`;
  }
  if (filePath.startsWith(HOME + "/")) {
    return `~/${filePath.slice(HOME.length + 1)}`;
  }
  return filePath;
}

function extractProject(cwd: string): string {
  return cwd.split("/").pop() || cwd;
}

async function main() {
  let input: HookInput;
  try {
    input = JSON.parse(await new Response(Deno.stdin.readable).text());
  } catch {
    return;
  }

  if (input.hook_event_name !== "InstructionsLoaded") return;

  const event: InstructionsEvent = {
    ts: new Date().toISOString(),
    file: shortenPath(input.file_path, input.cwd),
    type: input.memory_type,
    reason: input.load_reason,
    session: input.session_id,
    project: extractProject(input.cwd),
  };

  await maybeRotate(LOG_PATH);
  await Deno.writeTextFile(LOG_PATH, JSON.stringify(event) + "\n", {
    append: true,
  });
}

main();
