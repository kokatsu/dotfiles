#!/usr/bin/env bash
# Behavior tests for the rule set the AI writing hook enforces. Renovate
# bumps @textlint-ja/textlint-rule-preset-ai-writing without review, so the rules
# in effect and the shape of a few decisive inputs are pinned here. The hook's
# own branches are covered by test-ai-writing-hook.sh.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
config="$repo_root/.config/ai-writing/textlint-response.json"

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
  report=$(textlint --config "$config" --rulesdir "$repo_root/.config/ai-writing/rules" --format json --no-color "${case_file[@]}") || status=$?
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

print_config=$(textlint --config "$config" --rulesdir "$repo_root/.config/ai-writing/rules" --print-config)

# 有効なルールの集合を固定する。preset が増減すると 20 個の false 指定が追随できず、
# 検査範囲が黙って変わるため。
expected_rules=$(
  cat <<'RULES'
@textlint-ja/ai-writing/no-ai-colon-continuation
@textlint-ja/ai-writing/no-ai-emphasis-patterns
@textlint-ja/ai-writing/no-ai-hype-expressions
@textlint-ja/ai-writing/no-ai-list-formatting
ja-technical-writing/ja-no-redundant-expression
ja-technical-writing/max-ten
ja-technical-writing/no-mix-dearu-desumasu
no-pause-comma
no-prose-dash
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
[ "$(printf '%s' "$dearu_options" | jq -r '.preferInList')" = "" ] ||
  fail "no-mix-dearu-desumasu lost the list exemption"

# japanese-writing が禁止している形式と、その代替
expect_rule no-prose-dash '設定を確認します。補足──具体例です。' 'double dash in prose'
expect_rule no-prose-dash '# 設定—補足' 'em dash in a heading'
expect_rule no-prose-dash '設定–補足です。' 'en dash in prose'
expect_rule no-prose-dash '設定――補足です。' 'horizontal bars in Japanese prose'
expect_rule no-prose-dash '設定⸺補足です。' 'two-em dash in prose'
expect_rule no-prose-dash '設定⸻補足です。' 'three-em dash in prose'
expect_clean '設定を確認します。具体例です。' 'sentences without dashes'
expect_clean '> 引用──原文です。' 'quoted dash'
# shellcheck disable=SC2016
expect_clean '識別子は `a—b` です。' 'inline code dash'
# shellcheck disable=SC2016
expect_clean '```text
a──b
```' 'fenced dash'
expect_clean '[参照](https://example.com/a—b)' 'dash in a URL'
expect_clean 'These settings—like the other defaults—remain unchanged.' 'English prose outside the Japanese rule'
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
  'これは設定ファイルである。

それ以外は無効である。' 'a body written only in dearu'

expect_no_rule ja-technical-writing/no-mix-dearu-desumasu \
  'これは設定ファイルです。

- ルールはここで定義する
- 例外は無効化する' 'list items exempt from the style check'

expect_no_rule ja-technical-writing/sentence-length \
  'この設定ファイルは textlint のルールを制御するためのものであり、AI 文体の検出と日本語技術文書の規範のうち必要なものだけを有効にして、それ以外はすべて明示的に無効化しているという構成になっていますが、これは preset の個別ルールが NODE_PATH のトップレベルで解決できないためです。' \
  'long sentences in chat'

expect_rule ja-technical-writing/max-ten \
  'まず、設定を読み、次に、値を比べ、最後に、結果を書く。' 'four commas in a sentence'
expect_no_rule ja-technical-writing/max-ten \
  'まず、設定を読み、値を比べ、結果を書く。' 'three commas in a sentence'
expect_rule no-pause-comma '設定ファイルと、スクリプトを更新する。' 'comma after a parallel と'
expect_rule no-pause-comma 'Claude Code と、Codex を使う。' 'comma after と that follows an English noun'
expect_clean '実行すると、ログが出る。' 'conditional と'
expect_clean '完了したと、報告した。' 'quotative と'
expect_clean '設定ファイルとスクリプトを更新する。' 'parallel と without a comma'
expect_rule no-pause-comma 'レビューの指摘を、ドキュメントで確かめる。' 'comma after a short object'
expect_clean 'レビューの指摘をドキュメントで確かめる。' 'short object without a comma'
expect_clean '昨日の会議で決まった三つの変更点を、明日までに反映する。' 'object clause'
expect_clean '一次資料を取得していない第三者記事の扱いを、決める。' 'long object'
expect_clean '設定を、利用者が変える。' 'another subject after the comma'
expect_clean '鍵を、なくした人に届けた。' 'comma that keeps the object off the next clause'
expect_clean 'これを、明日までに直す。' 'pronoun object'
expect_clean '設定を、ログを、順に確かめる。' 'list of objects'
expect_rule no-pause-comma 'textlint の設定を、明日確かめる。' 'English words count as one character'
expect_rule no-pause-comma '日本語技術文書の規範を、明日読む。' 'ten-character object'
expect_clean '日本語技術文書の規範集を、明日読む。' 'eleven-character object'
expect_clean '設定を、**利用者**が変える。' 'subject behind inline markup'
expect_rule no-pause-comma '設定ファイルと、スクリプトは更新済みです。' 'coordination closed by は'
expect_rule no-pause-comma '設定ミスと、手順漏れを報告した。' 'coordinated object of a quoting verb'
expect_rule no-pause-comma '設定ファイルと、スクリプトは管理者が説明します。' 'coordinated topic of a quoting verb'
expect_clean '完了と、報告した。' 'quotative と before a verb'
# shellcheck disable=SC2016
expect_rule no-pause-comma '`config.json` と、`settings.json` を比較する。' 'coordination of inline code'
expect_rule no-pause-comma '設定を、保存する。ログを確認する。' 'next sentence does not make a list'
expect_rule no-pause-comma '明日、設定を、保存する。' 'introductory comma before the object'
expect_rule no-pause-comma '設定を、**保存する**。' 'predicate behind inline markup'
# shellcheck disable=SC2016
expect_rule no-pause-comma '設定を、`foo` で保存する。' 'inline code after the comma'

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
mkdir -p "$workdir/ai-writing"
ln -s "$config" "$workdir/ai-writing/textlint-response.json"
ln -s "$repo_root/.config/ai-writing/rules" "$workdir/ai-writing/rules"
run_real_hook() {
  printf '%s\n' "$1" >"$workdir/$2"
  jq -cn --arg p "$workdir/$2" '{tool_name: "Write", tool_input: {file_path: $p}}' |
    XDG_CONFIG_HOME="$workdir" bash "$repo_root/.config/ai-writing/check-ai-writing.sh"
}
for message in '> これは革命的な技術です。' '必要に応じて設定します。'; do
  [ -z "$(run_real_hook "$message" note.md)" ] || fail "hook should pass: $message"
done
run_real_hook 'これは革命的な技術です。' note.md | jq -e '.decision == "block"' >/dev/null ||
  fail "hook should still block unquoted hype"
run_real_hook '<html><body>
<p>設定します。</p>
<p>これは革命的な技術です。</p>
</body></html>' page.html |
  jq -e '.decision == "block" and (.reason | contains("line 3,"))' >/dev/null ||
  fail "hook should block hype in an HTML file at its source line"

# no-pause-comma tokenizes a whole block with inline code replaced, so its
# report must map back to the comma in the source.
# shellcheck disable=SC2016
printf '😀設定と、ログを確認する。\n\n**太字**の`a`と、ログを確認する。\n' >"$workdir/range.md"
range_report=$(textlint --config "$config" --rulesdir "$repo_root/.config/ai-writing/rules" --format json "$workdir/range.md") || true
printf '%s' "$range_report" |
  node -e '
    const fs = require("fs");
    const source = fs.readFileSync(process.argv[1], "utf8");
    const ranges = JSON.parse(fs.readFileSync(0, "utf8"))[0].messages
      .filter((m) => m.ruleId === "no-pause-comma")
      .map((m) => source.slice(...m.range));
    process.exit(ranges.length === 2 && ranges.every((c) => c === "、") ? 0 : 1);
  ' "$workdir/range.md" || fail "no-pause-comma should report the comma itself"

config="$repo_root/.textlintrc-commit.json"
expect_rule terminology 'feat: update readme' 'README spelling'
expect_rule terminology 'feat: update readmes' 'READMEs spelling'
expect_clean 'feat: update README and READMEs' 'canonical README spelling'
run_cases

printf 'textlint configs: rule set, response and commit cases, and real hook verified\n'
