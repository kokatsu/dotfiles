#!/usr/bin/env bash
# Behavior tests for the rule set the AI writing Stop hook enforces. Renovate
# bumps @textlint-ja/textlint-rule-preset-ai-writing without review, so the rules
# in effect and the shape of a few decisive inputs are pinned here. The hook's
# own branches are covered by test-ai-writing-hook.sh.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
config="$repo_root/.config/claude/hooks/textlint-response.json"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/cases"

fail() {
  printf '%s\n' "$1" >&2
  return 1
}

# textlint は起動だけで約 1.5 秒かかるので、ケースはファイルに溜めて
# run_cases で設定ごとに 1 回だけ起動する
case_count=0
case_file=()
case_kind=()
case_rule=()
case_label=()

add_case() {
  local file="$workdir/cases/case-$case_count.md"
  case_count=$((case_count + 1))
  printf '%s\n' "$3" >"$file"
  case_file+=("$file")
  case_kind+=("$1")
  case_rule+=("$2")
  case_label+=("$4")
}

expect_rule() { add_case rule "$1" "$2" "$3"; }
expect_no_rule() { add_case no_rule "$1" "$2" "$3"; }
expect_clean() { add_case clean '' "$1" "$2"; }

run_cases() {
  local report status=0 i found
  # textlint は指摘があると終了コード 1 を返すので、それは失敗として扱わない
  report=$(textlint --config "$config" --format json --no-color "${case_file[@]}") || status=$?
  [ "$status" -le 1 ] || fail "textlint failed with exit status $status"
  printf '%s' "$report" |
    jq -e --argjson n "${#case_file[@]}" 'type == "array" and length == $n and all(.[]; .messages | type == "array")' >/dev/null ||
    fail "textlint did not return one report per case"
  for i in "${!case_file[@]}"; do
    found=$(printf '%s' "$report" | jq -r --arg f "${case_file[i]}" '.[] | select(.filePath == $f) | .messages[].ruleId' | sort -u)
    case ${case_kind[i]} in
    rule)
      printf '%s\n' "$found" | grep -qx -- "${case_rule[i]}" ||
        fail "expected ${case_rule[i]} to fire: ${case_label[i]}"
      ;;
    no_rule)
      if printf '%s\n' "$found" | grep -qx -- "${case_rule[i]}"; then
        fail "expected ${case_rule[i]} to stay silent: ${case_label[i]}"
      fi
      ;;
    clean)
      [ -z "$found" ] || fail "expected no finding, got: $found (${case_label[i]})"
      ;;
    esac
  done
  case_file=()
  case_kind=()
  case_rule=()
  case_label=()
}

print_config=$(textlint --config "$config" --print-config)

# 有効なルールの集合を固定する。preset が増減すると 21 個の false 指定が追随できず、
# 検査範囲が黙って変わるため。
expected_rules=$(
  cat <<'RULES'
@textlint-ja/ai-writing/no-ai-colon-continuation
@textlint-ja/ai-writing/no-ai-emphasis-patterns
@textlint-ja/ai-writing/no-ai-hype-expressions
@textlint-ja/ai-writing/no-ai-list-formatting
ja-technical-writing/ja-no-redundant-expression
ja-technical-writing/no-mix-dearu-desumasu
RULES
)
actual_rules=$(printf '%s' "$print_config" | jq -r '.rule[].id' | sort)
if [ "$actual_rules" != "$expected_rules" ]; then
  printf 'enabled rules changed:\n%s\n' "$(diff <(printf '%s\n' "$expected_rules") <(printf '%s\n' "$actual_rules") || true)" >&2
  exit 1
fi

# オプション名が変わると textlint はエラーにせず既定値に戻る。
dearu_options=$(
  printf '%s' "$print_config" |
    jq -c '.rule[] | select(.id == "ja-technical-writing/no-mix-dearu-desumasu") | .options'
)
[ "$(printf '%s' "$dearu_options" | jq -r '.preferInBody')" = ですます ] ||
  fail "no-mix-dearu-desumasu lost preferInBody"
[ "$(printf '%s' "$dearu_options" | jq -r '.preferInList')" = "" ] ||
  fail "no-mix-dearu-desumasu lost the list exemption"

# japanese-writing が禁止している形式と、その代替
expect_rule @textlint-ja/ai-writing/no-ai-list-formatting \
  '- **用語**: 説明の本文' 'bold and colon in a list item'
expect_clean '- **用語** は説明の本文です' 'the prescribed replacement'
expect_clean '| 用語 | 説明 |
|---|---|
| **Biome** | JavaScript のリンタです |' 'bold inside a table cell'

expect_rule ja-technical-writing/ja-no-redundant-expression \
  'パッケージの更新を実行します。' 'redundant expression'
# 拮抗した比率では発火しないため、ですます側に寄せた入力を使う
expect_rule ja-technical-writing/no-mix-dearu-desumasu \
  'これは設定ファイルです。

ルールをここで制御します。

それ以外は無効である。' 'mixed style in the body'

expect_no_rule ja-technical-writing/no-mix-dearu-desumasu \
  'これは設定ファイルです。

- ルールはここで定義する
- 例外は無効化する' 'list items exempt from the style check'

expect_no_rule ja-technical-writing/sentence-length \
  'この設定ファイルは textlint のルールを制御するためのものであり、AI 文体の検出と日本語技術文書の規範のうち必要なものだけを有効にして、それ以外はすべて明示的に無効化しているという構成になっていますが、これは preset の個別ルールが NODE_PATH のトップレベルで解決できないためです。' \
  'long sentences in chat'

expect_clean '> これは革命的な技術です。' 'quoted hype remains verbatim'
expect_clean '> - **用語**: 説明の本文' 'quoted list remains verbatim'
expect_clean '> 引用の冒頭です。
> これは革命的な技術です。' 'multiline block quote'
expect_clean '> > これは革命的な技術です。' 'nested quote'
expect_rule @textlint-ja/ai-writing/no-ai-hype-expressions \
  '> 引用は維持します。

これは革命的な技術です。' 'body after a quote is still checked'
expect_clean '必要に応じて設定します。' 'advice does not block a response'
expect_clean '```text
これは革命的な技術です。
```' 'code remains verbatim'
run_cases

# Also exercise the actual hook with the symlink layout Home Manager deploys.
mkdir -p "$workdir/claude/hooks"
ln -s "$config" "$workdir/claude/hooks/textlint-response.json"
run_real_hook() {
  jq -cn --arg m "$1" '{last_assistant_message: $m, stop_hook_active: false}' |
    XDG_CONFIG_HOME="$workdir" bash "$repo_root/.config/claude/hooks/check-ai-writing.sh"
}
for message in '> これは革命的な技術です。' '必要に応じて設定します。'; do
  [ -z "$(run_real_hook "$message")" ] || fail "hook should pass: $message"
done
run_real_hook 'これは革命的な技術です。' | jq -e '.decision == "block"' >/dev/null ||
  fail "hook should still block unquoted hype"

config="$repo_root/.textlintrc-commit.json"
expect_rule terminology 'feat: update readme' 'README spelling'
expect_rule terminology 'feat: update readmes' 'READMEs spelling'
expect_clean 'feat: update README and READMEs' 'canonical README spelling'
run_cases

printf 'textlint configs: rule set, response and commit cases, and real hook verified\n'
