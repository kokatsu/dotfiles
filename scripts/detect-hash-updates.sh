#!/usr/bin/env bash
# detect-hash-updates.sh — Renovate PR で version が変わった bespoke パッケージを検出し、
# pr.yml の update ステップが読む GitHub Actions output (key=value、1 行 1 件) を
# stdout に出す。
#
# Usage: detect-hash-updates.sh <base-ref>      例: detect-hash-updates.sh origin/main
#
# 判定は「Renovate コメント直後の version が base-ref と異なるか」で行う。差分に
# パッケージ名が現れるかどうかでは、コメント修正や同じファイル内の別パッケージの更新
# でも反応してしまい、package-lock.json の無駄な再生成と version 不変のコミットを積む。
#
# 出力:
#   has_<key>=true / version_<key>=<ver>   version が変わったパッケージごと
#   packages=<name ver, name ver>           コミットメッセージ用
#   has_karabinerts_deno_lock=true          karabiner-config/deno.{json,lock} が変わったとき
#   has_flake_nix=true                      flake.nix が変わったとき

set -euo pipefail

BASE=${1:?usage: $0 <base-ref>}

# name|output_key|file|grep_after|renovate_grep
#   grep_after    : Renovate コメントから version 行までの最大行数 (grep -A)
#   renovate_grep : Renovate コメントの grep パターン
# scripts/test-hash-patterns.sh の BESPOKE テーブルと対で保守する
PACKAGES=(
  'cssmodules-language-server|cssmodules_language_server|nix/overlays/source-builds.nix|20|# Renovate:.*depName=.*cssmodules-language-server'
  'vite-plus|vite_plus|nix/overlays/npm-packages.nix|20|# Renovate:.*depName=vite-plus'
  'textlint-rule-preset-ai-writing|textlint_rule_preset_ai_writing|nix/overlays/npm-packages.nix|20|# Renovate:.*depName=@textlint-ja/textlint-rule-preset-ai-writing'
  'codex|codex|nix/overlays/binary-releases.nix|30|# Renovate:.*depName=openai/codex'
  'x-api-playground|x_api_playground|nix/overlays/source-builds.nix|20|# Renovate:.*depName=.*playground'
  'claude-code|claude_code|nix/overlays/binary-releases.nix|20|# Renovate:.*depName=claude-code'
)

# $1=ファイル, $2=grep -A の行数, $3=Renovate コメントのパターン
# コメントから N 行以内の最初の version = "..." を返す (無ければ空)
extract_version() {
  grep -A "$2" "$3" "$1" 2>/dev/null | sed -n 's/.*version = "\([^"]*\)".*/\1/p' | head -1 || true
}

# overlay 由来の文字列をシェルへ展開する前に検証する (インジェクション対策)
validate_version() {
  local name="$1" val="$2"
  if ! [[ "$val" =~ ^[0-9a-zA-Z.+_-]+$ ]]; then
    echo "::error::Invalid version format for $name: $val" >&2
    exit 1
  fi
}

base_file=$(mktemp)
trap 'rm -f "$base_file"' EXIT

packages=""
for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r name key file after pattern <<<"$entry"

  current=$(extract_version "$file" "$after" "$pattern")
  [[ -n "$current" ]] || continue
  validate_version "$name" "$current"

  # base 側にファイルが無い (新規追加) 場合は空 = 変更ありとして扱う
  git show "$BASE:$file" >"$base_file" 2>/dev/null || : >"$base_file"
  previous=$(extract_version "$base_file" "$after" "$pattern")
  [[ "$current" != "$previous" ]] || continue

  echo "has_${key}=true"
  echo "version_${key}=${current}"
  packages="${packages:+$packages, }$name $current"
done

# karabiner-config/ は nix/overlays/ の外にあるので、パスを絞った差分で別に見る
if git diff --name-only "$BASE" -- karabiner-config/ | grep -qE '^karabiner-config/(deno\.json|deno\.lock)$'; then
  echo "has_karabinerts_deno_lock=true"
fi

# flake.nix の変更は sync-flake-inputs.sh が実際に走る条件そのもので、
# そのスクリプトが Deno ヘルパーで input を抽出する
if ! git diff --quiet "$BASE" -- flake.nix; then
  echo "has_flake_nix=true"
fi

echo "packages=$packages"
