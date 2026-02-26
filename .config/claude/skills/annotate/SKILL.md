---
name: annotate
description: Read user's inline notes in plan.md and update the plan accordingly. Never implements code.
allowed-tools:
  - Read
  - Glob
  - Grep
  - Task
  - Write
  - Edit
---

# Annotate Skill

Process user's inline annotations in plan.md and update the document accordingly.

## Usage

```text
/annotate
```

No arguments needed. Reads `plan.md` in the current working directory.

## Workflow

1. **Read `plan.md`** carefully, looking for user-added inline notes
2. **Identify all annotations** — user notes may appear as:
   - Lines starting with `>`, `NOTE:`, `TODO:`, `FIXME:`, or `!!`
   - Text in bold or italic that wasn't in the original plan
   - Comments wrapped in `<!-- -->` or `[[ ]]`
   - Any text that clearly differs in tone from the AI-generated plan
3. **Address every single note** — modify the plan according to each annotation
4. **Remove the annotation markers** after incorporating the feedback
5. **Write the updated plan** back to `plan.md`

## Critical Rules

- **Do NOT implement anything.** Only update the plan document.
- **Address ALL notes.** Do not skip any annotation, no matter how small.
- If a note says to remove a section, remove it entirely.
- If a note corrects an assumption, update all affected parts of the plan (not just the annotated line).
- If a note is ambiguous, keep the annotation and ask the user for clarification.
- Maintain the todo list — update it to reflect any plan changes.

## Output

After updating `plan.md`, provide a summary of changes:

- List each annotation found and how it was addressed
- Highlight any annotations that were ambiguous

End with: "再度レビューしてメモを追加するか、問題なければ `/implement` で実装を開始できます。"
