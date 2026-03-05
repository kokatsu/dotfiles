---
name: commit
description: Create a git commit following Conventional Commits. Use when the user asks to commit changes.
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Commit Skill

Create a git commit following Conventional Commits (`@commitlint/config-conventional`).

## Usage

```text
/commit
```

## Workflow

1. Run `git status` and `git diff --staged` to understand changes
2. If there are unstaged changes, ask the user before proceeding
3. Generate an appropriate commit message based on the staged changes
4. Present the generated commit message to the user and wait for approval
5. Execute the commit

## Commit Convention

Follow Conventional Commits (`@commitlint/config-conventional`).

Project-specific guidelines:

- Config file tweaks (e.g. renovate.json5, flake.nix settings) → `chore`, not `feat`
- Adding a new overlay or tool → `feat`
- Dependency version bumps → `build(deps)`

## Critical Rules

- **Only commit staged changes** — never `git add` unstaged changes without explicit permission
- **Commit messages must be in English** — both subject and body
- **Use HEREDOC format to pass messages** — avoids shell escaping issues
- **Never use `--no-verify`** — if a hook fails, investigate and fix the root cause
- **Always get user approval before committing** — present the message and do not commit without confirmation
- **Only amend when the user explicitly requests it**
