---
name: plan
description: Create a detailed implementation plan in plan.md. Never implements code. Use after /research or when planning a feature.
allowed-tools:
  - Read
  - Glob
  - Grep
  - Task
  - Write
---

# Plan Skill

Create a detailed implementation plan based on the current codebase and any existing research.

## Usage

```text
/plan <feature description or change request>
```

## Workflow

1. **Read `research.md`** if it exists in the current directory — use it as context
2. **Read relevant source files** to understand the current implementation
3. **Write `plan.md`** with a detailed implementation plan

## Plan Document Structure

Write `plan.md` with the following sections:

1. **Goal** — What we're building or changing, and why
2. **Approach** — High-level strategy and architectural decisions
3. **Detailed Changes** — For each file to be modified:
   - File path
   - What changes are needed
   - Code snippets showing the actual changes
4. **Considerations & Trade-offs** — Alternative approaches considered and why this one was chosen
5. **Todo List** — Granular checklist of all tasks, grouped by phase:

   ```markdown
   ## Todo

   ### Phase 1: <name>
   - [ ] Task 1
   - [ ] Task 2

   ### Phase 2: <name>
   - [ ] Task 3
   - [ ] Task 4
   ```

## Critical Rules

- **Do NOT implement anything.** Planning only. No code changes to the project.
- **Base the plan on the actual codebase.** Read source files before suggesting changes.
- Include concrete code snippets — not vague descriptions.
- If a reference implementation is provided in the arguments, study it and adapt the approach.
- The todo list must be granular enough to track progress during implementation.

## Output

Always write the plan to `plan.md`. After writing, give a brief summary to the user.
End with: "plan.mdをレビューしてインラインメモを追加した後、`/annotate` で反映できます。"
