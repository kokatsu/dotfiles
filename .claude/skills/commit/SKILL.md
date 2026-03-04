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

Conventional Commits (`@commitlint/config-conventional`) に従ってコミットを作成する。

## Usage

```text
/commit
```

## Workflow

1. `git status` と `git diff --staged` を確認して変更内容を把握
2. ステージされていない変更があればユーザーに確認
3. 変更内容に基づいて適切なコミットメッセージを生成
4. コミットを実行

## Commit Convention

Follow Conventional Commits (`@commitlint/config-conventional`).

Project-specific guidelines:

- Config file tweaks (e.g. renovate.json5, flake.nix settings) → `chore`, not `feat`
- Adding a new overlay or tool → `feat`
- Dependency version bumps → `build(deps)`

## Critical Rules

- **ステージされた変更のみコミット** — 未ステージの変更は勝手にaddしない
- **コミットメッセージは英語** — 本文も英語で記述
- **HEREDOC形式でメッセージを渡す** — シェルエスケープの問題を回避
- **`--no-verify` は使わない** — hookが失敗したら原因を調査して修正
- **amend はユーザーが明示的に要求した場合のみ**
