---
name: spec
description: Spec-Driven Development workflow with four phases — research (deep-read a codebase area into research.md), plan (produce plan.md from research), annotate (apply the user's inline notes in plan.md), implement (execute plan.md). Use when the user asks to research/investigate a module, plan/design a feature, process plan annotations, or implement a prepared plan. Triggered by phrases like "調査して" "plan を作って" "research.md / plan.md", or by the user running `/spec:research` `/spec:plan` `/spec:annotate` `/spec:implement`.
argument-hint: "<phase> [phase-args...]   where phase is research|plan|annotate|implement"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Task
  - Edit
  - Write
  - Bash
---

# Spec Skill — Spec-Driven Development Workflow

Four-phase workflow producing `research.md` → `plan.md` → (human annotation) → implementation.
Each phase persists to a file so the workflow can span multiple sessions.

## Phase Dispatch

The first argument token selects the phase. Read **only** the matching reference — they are progressive-disclosure documents.

| Phase | Reference | Purpose |
|---|---|---|
| `research` | [references/research.md](references/research.md) | Deep-read a codebase area, write `research.md` |
| `plan` | [references/plan.md](references/plan.md) | Produce `plan.md` with parallel architecture options |
| `annotate` | [references/annotate.md](references/annotate.md) | Apply user's inline notes in `plan.md` |
| `implement` | [references/implement.md](references/implement.md) | Execute `plan.md` end-to-end |

If the phase is omitted or ambiguous, ask the user which phase to run. Do **not** guess.

## Invocation Forms

All equivalent:

```text
/spec:research src/auth              # command form (preferred, namespaced)
Use the spec skill with phase=research and target=src/auth
```

When auto-triggered (no explicit command), infer the phase from the user's request and proceed.

## Shared Rules

- **Respond in the user's language** (Japanese for Japanese prompts, English otherwise).
- **Never mix phases.** Each invocation runs exactly one phase.
- **File locations are the current working directory**: `./research.md`, `./plan.md`. Do not write to the home or skill directory.
- **Do not implement during research/plan/annotate.** Only `implement` may edit source files.
- After finishing a phase, tell the user which `/spec:<next>` command to run next.
