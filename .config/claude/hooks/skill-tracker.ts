#!/usr/bin/env -S deno run --allow-read --allow-write=${CLAUDE_CONFIG_DIR},${HOME}/.claude,${HOME}/.config/claude --allow-env=HOME,CLAUDE_CONFIG_DIR

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  permission_mode: string;
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
  const decoder = new TextDecoder();
  const chunks: Uint8Array[] = [];
  for await (const chunk of Deno.stdin.readable) {
    chunks.push(chunk);
  }
  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const merged = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }

  let input: HookInput;
  try {
    input = JSON.parse(decoder.decode(merged));
  } catch {
    Deno.exitCode = 1;
    return;
  }

  const event = extractEvent(input);
  if (event) {
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
