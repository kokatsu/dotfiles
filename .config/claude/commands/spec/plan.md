---
description: Produce plan.md with parallel architecture options (spec workflow — plan phase)
argument-hint: <feature description or change request>
allowed-tools:
  - Read
  - Glob
  - Grep
  - Task
  - Write
  - Edit
---

Run the **plan** phase of the Spec-Driven Development workflow.

Follow the instructions in `skills/spec/references/plan.md`:

- Read `research.md` if present.
- Launch 3 code-architect agents in parallel (minimal / clean / pragmatic).
- Synthesize a single `plan.md` with file-level changes and a granular Todo list.

Feature: $ARGUMENTS
