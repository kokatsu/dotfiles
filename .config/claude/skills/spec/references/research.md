# Spec · Research Phase

Deeply investigate a specified area of the codebase and produce `research.md`.

## Arguments

`$ARGUMENTS` — target folder, module, or system description
(e.g., `src/auth`, `payment processing`, `the event dispatcher`)

## Workflow

### 1. Launch 3 Explore agents in parallel

**Always prefer parallel investigation over sequential reading.** Use the `Task` tool to launch exactly three `Explore` agents simultaneously (one message, three tool calls). Each targets a different lens:

| Agent | Lens | Prompt template |
|---|---|---|
| A | **Architecture & control flow** | "Map the architecture of `$TARGET`. Trace entry points, key abstractions, control flow, and major components. Return 5–10 key files to read." |
| B | **Similar features & patterns** | "Find features or modules similar to `$TARGET`. Explain how they solve analogous problems and what patterns they share. Return 5–10 key files." |
| C | **Data flow & external boundaries** | "Trace how data enters, transforms, and leaves `$TARGET`. Identify external dependencies, I/O boundaries, and persistence layers. Return 5–10 key files." |

Each agent returns a summary + file list. Use `subagent_type: Explore` with thoroughness `"medium"` (or `"very thorough"` for large targets).

### 2. Read the files agents surfaced

After agents finish, **read the union of their recommended files** yourself to verify claims and gather concrete line references. Deduplicate paths.

### 3. Write `research.md`

Structure:

1. **Overview** — What this system/module does at a high level
2. **Architecture** — Components, key files, entry points (with `file:line` refs)
3. **Data Flow** — How data moves, interfaces, persistence
4. **Key Implementation Details** — Patterns, conventions, edge cases
5. **Dependencies** — External libraries, internal modules
6. **Potential Issues / Observations** — Inconsistencies, risks, technical debt

## Critical Rules

- **Do NOT implement.** Research only.
- **Do NOT skim.** Trace function bodies, not just signatures.
- All non-trivial claims must cite `path:line`.
- If the user's arguments include a reference implementation, treat it as a must-read baseline.
- If bug hunting is the goal, keep investigating until every finding has evidence.

## Output

After writing `research.md`, give the user a brief verbal summary of key findings and end with:

> `research.md` を作成しました。`/spec:plan <feature>` で実装計画を作れます。
