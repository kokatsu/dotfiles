# Spec · Plan Phase

Produce `plan.md` — a detailed, file-level implementation plan with a Todo checklist.

## Arguments

`$ARGUMENTS` — feature description or change request
(e.g., `add OAuth login`, `migrate storage to Postgres`)

## Workflow

### 1. Ingest context

- If `research.md` exists in the current directory, read it in full and treat it as the authoritative codebase map.
- If it does not exist, read the most relevant source files directly (use Glob/Grep to locate them).

### 2. Launch 3 code-architect agents in parallel

Use the `Task` tool with three simultaneous invocations, each exploring a distinct trade-off space (mirrors `feature-dev` Phase 4):

| Agent | Focus | Prompt template |
|---|---|---|
| A | **Minimal change** | "Design the smallest possible change to achieve `$FEATURE`. Maximize reuse of existing abstractions. Return file-level changes with code snippets." |
| B | **Clean architecture** | "Design an elegant, maintainable implementation of `$FEATURE`. Prefer clean abstractions over shortcuts. Return file-level changes with code snippets." |
| C | **Pragmatic balance** | "Design `$FEATURE` balancing speed-to-ship with medium-term maintainability. Return file-level changes with code snippets." |

Use `subagent_type: feature-dev:code-architect` if available, otherwise `general-purpose`.

### 3. Synthesize one plan

**Do not output three plans.** After reading all three agent reports:

1. Pick one approach (usually a blend) and state **why** in the "Considerations & Trade-offs" section.
2. Summarize the other two approaches as rejected alternatives with one-line reasons.

### 4. Write `plan.md`

Structure:

1. **Goal** — What we are building/changing, and why
2. **Approach** — Chosen strategy, core architectural decisions
3. **Detailed Changes** — For each file to be modified or created:
   - File path
   - What changes are needed
   - Concrete code snippets (not vague descriptions)
4. **Considerations & Trade-offs** — Alternatives considered, why this one won
5. **Todo** — Granular checklist grouped by phase:

   ```markdown
   ## Todo

   ### Phase 1: <name>
   - [ ] Task 1
   - [ ] Task 2

   ### Phase 2: <name>
   - [ ] Task 3
   ```

## Critical Rules

- **Do NOT implement.** Planning only.
- Plan must be based on actual source files — verify every claim before writing it.
- Include concrete code snippets, not prose descriptions.
- Todo list must be granular enough to track mid-implementation progress.

## Output

After writing `plan.md`, give a brief summary and end with:

> `plan.md` を作成しました。インラインメモを追記して `/spec:annotate` で反映するか、そのまま `/spec:implement` で実装できます。
