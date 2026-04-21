# Spec · Annotate Phase

Process the user's inline notes in `plan.md` and update the document accordingly.

## Arguments

None. Reads `plan.md` in the current working directory.

## Workflow

1. **Read `plan.md`** end-to-end. Look for user-added annotations, which may appear as:
   - Lines starting with `>`, `NOTE:`, `TODO:`, `FIXME:`, or `!!`
   - Newly added **bold** / _italic_ text that wasn't in the AI-generated plan
   - `<!-- ... -->` HTML comments or `[[ ... ]]` markers
   - Any text whose tone clearly differs from the AI-written baseline

2. **Address every single annotation.** For each:
   - If it corrects an assumption, **propagate the correction** everywhere the assumption influenced the plan.
   - If it says to remove a section, remove it completely.
   - If it adds a requirement, integrate it into the relevant phase/files.
   - If it is ambiguous, leave the annotation in place and ask the user for clarification (do not guess).

3. **Remove the annotation markers** after incorporating the feedback (keep only the ambiguous ones).

4. **Update the Todo checklist** to reflect any scope changes.

5. **Write the updated `plan.md`.**

## Critical Rules

- **Do NOT implement.** Only update the plan document.
- **Address ALL notes.** Skip nothing; partial application is worse than flagging ambiguity.
- A correction at one point usually implies changes elsewhere — trace consequences before concluding.
- Preserve the plan's section structure (Goal / Approach / Detailed Changes / Considerations / Todo).

## Output

Summarize the applied changes:

- List each annotation found and how it was addressed
- Highlight annotations left ambiguous (if any)

End with:

> `plan.md` を更新しました。再度メモを追記するか、問題なければ `/spec:implement` で実装を開始できます。
