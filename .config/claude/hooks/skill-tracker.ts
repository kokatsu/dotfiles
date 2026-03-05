#!/usr/bin/env -S deno run --allow-read --allow-write=${CLAUDE_CONFIG_DIR},${HOME}/.claude,${HOME}/.config/claude --allow-env=HOME,CLAUDE_CONFIG_DIR

interface HookInput {
  session_id: string;
  cwd: string;
  hook_event_name: string;
  prompt?: string;
  tool_name?: string;
  tool_input?: Record<string, unknown>;
}

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

const BUILTINS = new Set([
  "bug",
  "clear",
  "compact",
  "config",
  "cost",
  "doctor",
  "fast",
  "help",
  "init",
  "login",
  "logout",
  "memory",
  "model",
  "permissions",
  "review",
  "status",
  "tasks",
  "terminal-setup",
  "vim",
]);

async function main() {
  let input: HookInput;
  try {
    input = JSON.parse(await new Response(Deno.stdin.readable).text());
  } catch {
    return;
  }

  const event = extractEvent(input);
  if (event) {
    await maybeRotate(LOG_PATH);
    await Deno.writeTextFile(LOG_PATH, JSON.stringify(event) + "\n", {
      append: true,
    });
  }
}

function extractEvent(input: HookInput): SkillEvent | null {
  // User-invoked: /skill-name in UserPromptSubmit
  if (input.hook_event_name === "UserPromptSubmit" && input.prompt) {
    const match = input.prompt.match(/^\/(\S+)(?:\s+(.*))?$/);
    if (match && !BUILTINS.has(match[1])) {
      return {
        ts: new Date().toISOString(),
        type: "user",
        skill: match[1],
        session: input.session_id,
        args: match[2]?.trim() || "",
        cwd: input.cwd,
      };
    }
  }

  // Auto-invoked: Skill tool in PreToolUse
  if (
    input.hook_event_name === "PreToolUse" &&
    input.tool_name === "Skill" &&
    input.tool_input
  ) {
    const skill = input.tool_input.skill as string;
    if (skill) {
      return {
        ts: new Date().toISOString(),
        type: "auto",
        skill,
        session: input.session_id,
        args: (input.tool_input.args as string) || "",
        cwd: input.cwd,
      };
    }
  }

  return null;
}

main();
