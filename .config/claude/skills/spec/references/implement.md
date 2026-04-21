# Spec · Implement Phase

Execute the full plan in `plan.md`: implement every task, mark progress, run checks continuously.

## Arguments

None. Reads `plan.md` in the current working directory.

## Workflow

1. **Read `plan.md`** in full — understand the Goal, Approach, Detailed Changes, and the complete Todo list.

2. **Implement tasks in the order the plan defines**, phase by phase.

3. **After each task completes, mark it done in `plan.md`**: `- [ ]` → `- [x]`. Do this incrementally so progress is visible to the user.

4. **Run the project's lint/typecheck/test commands continuously**:
   - Check project-local `CLAUDE.md` for the canonical commands.
   - Run them after each phase, not only at the end.
   - Fix issues as they surface; do not accumulate failures.

5. **Do not stop** until every Todo is checked off.

6. **If you encounter something not covered by the plan**:
   - Note it inline in `plan.md` (new subsection "## Deviations") with a brief reason.
   - Continue with the remaining tasks unless the deviation makes the plan unsafe.

## Implementation Rules

- **Implement everything in the plan.** No cherry-picking, no skipping.
- **Do not over-engineer.** Stick to what the plan specifies.
- **Do not add unnecessary comments or docstrings.** Follow the CLAUDE.md guidance for commenting.
- **TypeScript**: do not use `any` or `unknown` unless the plan explicitly authorizes it.
- **Follow the project's existing conventions** (formatter, import style, naming, file layout).

## Output

When all Todos are complete:

1. Summarize what was built (files changed, key decisions, any deviations recorded).
2. Report any issues the user should follow up on.
3. Do **not** commit unless the user asks — creating commits is a separate explicit step.
