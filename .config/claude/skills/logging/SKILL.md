---
name: logging
description: >-
  Review code for logging quality or add proper logging to code.
  Use when asked to "add logging", "review logging", "improve logs",
  "ログ追加", "ログレビュー", "ログ改善", "ログ実装".
  Also use when the user wants to replace print/console.log with proper logging,
  improve observability or debuggability, add error context for troubleshooting,
  or asks about logging best practices.
  Trigger phrases include "print文を置き換え", "エラーログ", "デバッグログ",
  "トラブルシュート", "observability", "ログ設計".
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

## Usage

```text
/logging [file path, directory, or description]
```

## Arguments

- `$ARGUMENTS`: File path, directory, or description of the analysis target (optional)
  - If omitted: Ask the user what to analyze

## Workflow

Load `${CLAUDE_SKILL_DIR}/guidelines.md`, then check the target named by `$ARGUMENTS` against it (5W1H, level appropriateness, security). Existing project conventions take precedence over the guidelines: adapt to the project's language, logging library, and style, and do not introduce a different library or format without the user's explicit approval.

Two modes:

- **Review** (default when intent is unclear, and whenever the request is phrased as a question such as "ログ大丈夫？" or "logging issues?"): report findings only; do not edit files.
- **Implement** (only when the user explicitly asks to add, fix, implement, improve, or replace logging): make the changes.

Sensitive-data leaks (passwords, tokens, PII) are reported before any other finding.

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
