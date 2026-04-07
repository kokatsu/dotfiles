---
name: logging
description: >-
  Review code for logging quality or add proper logging to code.
  Use when asked to "add logging", "review logging", "improve logs",
  "ログ追加", "ログレビュー", "ログ改善", "ログ実装".
argument-hint: "<file path, directory, or description>"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - Bash
  - TaskCreate
  - TaskUpdate
---

# Logging Skill

Review or implement proper application logging based on established guidelines.

**Respond to the user in the same language they use.**

## Usage

```text
/logging [file path, directory, or description]
```

## Arguments

- `$ARGUMENTS`: File path, directory, or description of the analysis target (optional)
  - If omitted: Ask the user what to analyze

## Workflow

1. **Read guidelines** — Load `${CLAUDE_SKILL_DIR}/guidelines.md`
2. **Detect existing setup** — Identify the project's logging library, format, and conventions before suggesting changes
3. **Identify target** — Determine which files/modules to analyze based on `$ARGUMENTS`
4. **Analyze** — Check logging against guidelines (5W1H, level appropriateness, security)
5. **Act** — Report issues (review) or add/fix logging (implement)

## Critical Rules

- **Security findings are highest priority** — Sensitive data leaks (passwords, tokens, PII) must be flagged before any other issue
- **Review mode does not modify code** — Report findings only; never edit files unless explicitly asked to implement

## Output

### Review mode

Report findings as a table:

| File:Line | Severity | Issue | Recommendation |
|---|---|---|---|
| `auth.py:42` | HIGH | Password logged in plain text | Remove `password` from log fields |

### Implement mode

1. Make changes following guidelines and existing project conventions
2. Verify: build passes, existing tests unaffected
3. Summarize what was added/modified
