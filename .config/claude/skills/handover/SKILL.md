---
name: handover
description: Create a HANDOVER.md file summarizing the current session for context continuity. Use when switching sessions or before ending work.
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
---

# Handover Skill

現在のセッションの作業内容を要約し、次のセッションに引き継ぐための `HANDOVER.md` を生成する。

## Usage

```text
/handover
```

## Workflow

1. **既存の HANDOVER ファイルを確認** — `.claude/HANDOVER-*.md` があれば読んで前回の引き継ぎ内容を把握する
2. **現在のセッションを振り返る** — 会話の流れから以下を整理する:
   - 完了したタスク
   - 現在の進捗状況（変更したファイル、実行したコマンド）
   - 未完了の作業や次のステップ
   - 重要な技術的決定事項
   - 注意すべき問題点やワークアラウンド
3. **`.claude/HANDOVER.md` を作成/上書き** — 以下のフォーマットで書き出す

## Output Format

```markdown
# Handover

## 完了タスク
- タスク1の概要
- タスク2の概要

## 現在の状態
- コードベースの状態、変更されたファイルの要約

## 未完了・次のステップ
- 次にやるべきこと

## 重要な決定事項
- セッション中の技術的意思決定

## 注意事項
- 既知の問題、ワークアラウンド
```

## Critical Rules

- **簡潔に書く** — 次のセッションで素早く把握できるよう、各項目は1-2行で記述
- **不要なセクションは省略** — 該当がなければセクションごと省く
- **ファイルパスは相対パスで記載** — プロジェクトルートからの相対パス
- **出力先は `.claude/HANDOVER.md`** — 日付入りファイルではなく、常に同じファイルを上書きする
- 最後にユーザーに「HANDOVER.mdを作成しました」と伝える
