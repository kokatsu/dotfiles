---
name: implement
description: Execute the full implementation plan in plan.md. Implements all tasks, marks progress, and runs checks continuously.
allowed-tools:
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - Bash
  - Task
---

# Implement Skill

Execute the full implementation plan defined in plan.md.

## Usage

```
/implement
```

No arguments needed. Reads `plan.md` in the current working directory.

## Workflow

1. **Read `plan.md`** and understand the full plan and todo list
2. **Implement all tasks** in the order defined by the phases
3. **After completing each task**, update `plan.md` to mark it as done: `- [ ]` → `- [x]`
4. **Run type checking / linting** continuously to catch issues early
5. **Do not stop** until all tasks and phases are completed

## Implementation Rules

- **Implement everything in the plan.** Do not cherry-pick or skip tasks.
- **Do not add unnecessary comments or docstrings** to the code.
- **Do not use `any` or `unknown` types** (TypeScript projects).
- **Keep code clean and minimal.** No over-engineering beyond what the plan specifies.
- **Run relevant checks after each phase:**
  - TypeScript: `npx tsc --noEmit` or project-specific typecheck command
  - Nix: `statix check` and `alejandra --check`
  - Lua: `selene` with appropriate config
  - General: Use the project's configured linter
- **Mark progress in plan.md** as you go so the user can track status.
- If you encounter an issue not covered by the plan, note it in plan.md and continue with other tasks.

## Output

Update todo checkboxes in `plan.md` as you progress.
When all tasks are complete, summarize what was done and any issues encountered.
