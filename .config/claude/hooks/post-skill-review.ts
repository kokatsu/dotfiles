#!/usr/bin/env -S deno run --allow-read --allow-env=HOME,CLAUDE_CONFIG_DIR

interface HookInput {
  session_id: string;
  tool_name: string;
  tool_input: {
    skill: string;
    args?: string;
  };
  hook_event_name: string;
}

interface HookOutput {
  hookSpecificOutput: {
    additionalContext: string;
  };
}

const HOME = Deno.env.get("HOME")!;
const CONFIG_DIR = Deno.env.get("CLAUDE_CONFIG_DIR") || `${HOME}/.claude`;

async function findSkillFile(skill: string): Promise<string | null> {
  const candidates = [
    `${HOME}/.config/claude/skills/${skill}/SKILL.md`,
    `${CONFIG_DIR}/skills/${skill}/SKILL.md`,
  ];

  for (const path of candidates) {
    try {
      await Deno.stat(path);
      return path;
    } catch {
      // not found
    }
  }
  return null;
}

async function main() {
  let input: HookInput;
  try {
    input = JSON.parse(await new Response(Deno.stdin.readable).text());
  } catch {
    return;
  }

  if (input.tool_name !== "Skill" || !input.tool_input?.skill) return;

  const skill = input.tool_input.skill;
  const skillPath = await findSkillFile(skill);
  if (!skillPath) return;

  const output: HookOutput = {
    hookSpecificOutput: {
      additionalContext: [
        `[Skill Improvement Review]`,
        `The "${skill}" skill (${skillPath}) was just invoked.`,
        `After completing the skill's task, briefly evaluate whether the skill prompt worked effectively for this use case.`,
        `If you notice actionable improvements (unclear instructions, missing edge cases, unnecessary steps, structural issues),`,
        `append 1-3 concise suggestions to ${CONFIG_DIR}/skill-improvements.md in the format:`,
        ``,
        `## ${skill} - {date}`,
        `- suggestion`,
        ``,
        `Skip the review if the skill worked well. Keep this non-disruptive.`,
      ].join("\n"),
    },
  };

  console.log(JSON.stringify(output));
}

main();
