# pstack in Codex

pstack skills use Cursor names, and some tell you to read the Claude Code adapter. In Codex, read this file instead, once per session, and map each Cursor name with the tables below. `<pstack>` is the installed plugin root, `$CODEX_HOME/plugins/cache/cursor-plugins/pstack/<version>/`; resolve `<version>` by listing that directory, never hardcode it.

When a row here disagrees with the tools and arguments this session actually exposes, the session wins. Drop any field the tool schema rejects and say so in one line.

## Tools

| Cursor | Codex |
| --- | --- |
| `Task` | `spawn_agent` with a `task_name` and a `message` brief. Collect results with `wait_agent`, steer with `send_message`, and give a finished agent more work with `followup_task`. Older sessions expose `wait`, `send_input`, and `close_agent` instead. |
| `AskQuestion` | `request_user_input` when this turn lists it. Otherwise ask in plain text. |
| Open a todolist | `update_plan`. |
| Run another pstack skill (`/name` or "the **name** skill") | Read `<pstack>/skills/<name>/SKILL.md` and follow it. When you tell the user to type it, write `$pstack:<name>`. |
| `Grep`, `Glob` | `rg` in the shell. |

## Subagent fields

Pass `agent_type` only when the `spawn_agent` schema lists it. Without it, every agent is a general worker, and the brief carries the role.

| Cursor | Codex |
| --- | --- |
| `subagent_type: generalPurpose`, `readonly: false` | `agent_type: "worker"`, or omit. |
| `readonly: true` | `agent_type: "explorer"`, or omit. Neither blocks writes, so the brief also says "do not edit files", and you check `git status` afterward. |
| `poteto-agent`, `comment-sicko` | Start the brief with "Read `<pstack>/agents/<name>.md` and act as that agent", using the absolute path. Where that file says to search `~/.cursor/plugins/`, the parent gives `<pstack>` paths instead. |
| `run_in_background: true` | Omit. `spawn_agent` returns at once, and the agent runs until you wait on it. |
| `resume` | `followup_task` to the finished agent, or `resume_agent` in older sessions. |
| `environment: "cloud"`, `cloud_base_branch` | Skip, see Cursor-only features. |
| `environment: "local"` | Omit. |
| `file_attachments` | List the paths in the brief. |

## Models

Every subagent inherits the parent's model and reasoning effort: omit `model` and `reasoning_effort` on every `spawn_agent`, whatever slug or role line the skill names. There is no pstack model rule file in Codex.

Per-role model configuration is not supported in Codex. In `setup-pstack`, skip detecting models, choosing a budget, and writing the rule: write no file, tell the user `Not supported in Codex: per-role models; every role inherits the parent model.`, then continue with its verification-skill offers. Where `poteto-help` or another skill points the user to `/setup-pstack` for models, or says roles use their default models, say instead that every role inherits the parent model.

A step that compares different models, such as arena runners or a cross-judge pool, runs every participant on the same model here. Say `Not supported in Codex: cross-model comparison; all runners share the parent model.` once, then run the step anyway.

## Paths

| Cursor | Codex |
| --- | --- |
| `~/.cursor/plugins/`, the pstack plugin folder | `<pstack>` |
| `.cursor/rules/*.mdc`, always-applied rules | `AGENTS.md` |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `<pstack>/<path>` when that file exists. Read the local copy and never fetch it. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`. |

## Cursor-only features

Codex has no Cursor Automations, Bugbot, Cursor cloud agents, or built-in PR tool. When a step needs one, put one line in your reply, `Skipped in Codex: <step>. <reason>.`, then go on. Do not stop, ask, or retry. Triage Bugbot comments that already exist on a PR as ordinary review threads, and use the forge command the step gives (such as `gh pr create`) in place of a PR tool.
