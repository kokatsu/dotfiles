---
name: research
description: Deep-read a codebase area and write findings to research.md. Use for thorough investigation before planning.
allowed-tools:
  - Read
  - Glob
  - Grep
  - Task
  - Write
---

# Research Skill

Deeply investigate a specified area of the codebase and produce a detailed research document.

## Usage

```text
/research <target folder, module, or system to investigate>
```

## Workflow

1. **Deep-read** the target area thoroughly — read every file, understand every function, trace every flow
2. **Write findings** to `research.md` in the current working directory

## Research Document Structure

Write `research.md` with the following sections:

1. **Overview** — What this system/module does at a high level
2. **Architecture** — How components are organized, key files and their roles
3. **Data Flow** — How data moves through the system, key interfaces
4. **Key Implementation Details** — Important patterns, conventions, edge cases
5. **Dependencies** — External libraries, internal modules this depends on
6. **Potential Issues / Observations** — Anything noteworthy, inconsistencies, or risks

## Critical Rules

- **Do NOT implement anything.** This phase is research only.
- **Do NOT skim.** Read files deeply. Understand function bodies, not just signatures.
- Trace call chains end-to-end. Follow imports. Read tests if they exist.
- Write the research document in clear, structured markdown with code references (file:line).
- If the ARGUMENTS specify a bug hunt, keep researching until all bugs are found.

## Output

Always write findings to `research.md`. Never just summarize verbally in chat.
After writing, give a brief summary of key findings to the user.
