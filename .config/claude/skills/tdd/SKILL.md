---
name: tdd
description: >-
  Guide TDD workflow with Red-Green-Refactor cycle.
  Use when the user asks to "write tests first", "TDD", "test-driven",
  "テスト駆動", "TDDで実装", "テストファースト".
allowed-tools:
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - Bash
  - Task
---

# TDD Skill

Guide test-driven development using the Red-Green-Refactor cycle.

## Usage

```text
/tdd <feature description>
```

## Workflow

Repeat the following cycle for each behavior to implement:

### 1. Red — Write a Failing Test

- Write **one** test that describes the next desired behavior.
- Run the test suite and confirm it **fails** for the expected reason.
- If the test passes immediately, it is not testing new behavior — revise or remove it.

### 2. Green — Make It Pass

- Write the **minimum** code to make the failing test pass.
- Do not add logic beyond what the test requires.
- Run the test suite and confirm **all** tests pass.

### 3. Refactor — Improve the Code

- Clean up duplication, naming, and structure.
- Do **not** change observable behavior — tests must stay green.
- Run the test suite after every refactoring step.

### 4. Repeat

- Identify the next behavior and return to step 1.
- Stop when the feature description is fully covered.

## Testing Principles

### Test Behavior, Not Implementation

- Test through the **public interface** (exported functions, API endpoints, class methods).
- Never test private/internal functions directly — they are implementation details.
- A valid test should not break when you refactor internals without changing behavior.

### Mock Only at the Edges

- **Do mock**: HTTP calls, file system, databases, external services, clocks.
- **Do not mock**: internal modules, helper functions, or layers within your own codebase.
- Prefer real collaborators over mocks whenever practical.

### Practical Fakes Over Mocks

- Use in-memory databases (e.g., SQLite in-memory) instead of mocking query functions.
- Use HTTP fixtures or recorded responses instead of mocking HTTP clients.
- Use filesystem temp directories instead of mocking `fs` calls.

### Test Boundaries and Edge Cases

- Explicitly test both sides of boundary values (max, max+1, min, min-1, zero, empty).
- Include error inputs, resource failures, and timeout scenarios as separate Red-Green-Refactor cycles.
- When fixing a bug, start from Red: write a test that reproduces the bug before writing the fix.

### Keep Tests Readable

- Each test should read as a specification: **given / when / then**.
- Test names should describe the behavior, not the function name.
- One logical assertion per test — if a test needs many asserts, split it.

## Self-Check

Before moving from each phase, verify:

| Phase    | Check                                                              |
| -------- | ------------------------------------------------------------------ |
| Red      | Does the test fail? Is the failure message clear and expected?     |
| Green    | Do all tests pass? Did I write only the minimum code needed?      |
| Refactor | Do all tests still pass? Is the code cleaner than before?         |

Ask yourself after each cycle:

- "If I refactor the internals, will this test break?" — If yes, the test is too coupled to implementation.
- "Does this test describe a behavior a user/caller cares about?" — If no, reconsider the test.

## Output

- Produce test files and implementation files through the Red-Green-Refactor cycle.
- After completing all cycles, give a brief summary of the behaviors covered and test results.
