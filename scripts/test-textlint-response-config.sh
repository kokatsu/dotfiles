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
expect_rule no-pause-comma '昨日の会議で決まった三つの変更点を、明日までに反映する。' 'object clause'
expect_rule no-pause-comma '一次資料を取得していない第三者記事の扱いを、決める。' 'long object'
expect_rule no-pause-comma '資料への影響を、設計書に書く。' 'object behind への'
expect_rule no-pause-comma 'サーバーに届く経路を、どちらで作るか決める。' 'object modified by a verb'
expect_rule no-pause-comma '処理にかかる時間を、検証環境で測る。' 'object modified by a verb, adverbial noun'
expect_rule no-pause-comma '設定とログを、明日確かめる。' 'coordinated object'
expect_rule no-pause-comma '設定を、新しいファイルに書く。' 'adjective after the comma'
expect_clean '設定を、利用者が変える。' 'another subject after the comma'
expect_clean '鍵を、なくした人に届けた。' 'comma that keeps the object off the next clause'
expect_clean 'これを、明日までに直す。' 'pronoun object'
expect_clean '設定を、ログを、順に確かめる。' 'list of objects'
expect_clean 'A を、B を、順に直す。' 'list of English objects'
expect_rule no-pause-comma 'textlint の設定を、明日確かめる。' 'object with an English word'
expect_clean '設定を、**利用者**が変える。' 'subject behind inline markup'
expect_rule no-pause-comma '設定に、値を足す。' 'comma after に'
expect_rule no-pause-comma '一覧に、新しいファイルを足した。' 'comma after に before an adjective'
expect_rule no-pause-comma '本番環境に、設定を反映する。' 'comma after a compound noun and に'
expect_clean '設定に、利用者が値を足す。' 'another subject after the comma after に'
expect_rule no-pause-comma '設定に、ログに、順に書く。' 'repeated に is not taken for a list'
expect_rule no-pause-comma '画面に、縦に、線を引く。' 'place and direction closed by a comma'
expect_rule no-pause-comma '環境変数に、値を文字列に変換して設定する。' 'later に that is not parallel'
expect_rule no-pause-comma '会議室に、午後三時に集合する。' 'place and time are not parallel'
expect_rule no-pause-comma '設定に、ログに書く。' 'に phrases without a closing comma'
expect_rule no-pause-comma '画面に、縦に線を引く。' 'place and direction are not parallel'
expect_clean 'ここに、値を書く。' 'pronoun before に'
expect_clean 'さらに、値を足す。' 'adverb さらに'
expect_clean '次に、設定を直す。' 'conjunction 次に'
expect_clean '最後に、設定を直す。' 'sentence adverbial noun and に'
expect_clean '読めるように、順序を決める。' 'purpose clause ように'
expect_clean '失敗したときに、やり直す。' 'time clause ときに'
expect_clean '確かめるために、記録を残す。' 'purpose clause ために'
expect_clean '処理の前に、状態を確かめる。' 'adverbial noun 前に'
expect_clean '第一に、設定を直す。' 'ordinal 第一に'
expect_clean '設定をもとに、値を決める。' 'compound particle をもとに'
expect_clean '設定を、変更することで直す。' 'comma that keeps the object off the next verb'
expect_rule no-pause-comma '設定ファイルと、スクリプトは更新済みです。' 'coordination closed by は'
expect_rule no-pause-comma '設定ミスと、手順漏れを報告した。' 'coordinated object of a quoting verb'
expect_rule no-pause-comma '設定ファイルと、スクリプトは管理者が説明します。' 'coordinated topic of a quoting verb'
expect_clean '完了と、報告した。' 'quotative と before a verb'
expect_rule no-pause-comma '設定の読み込みと、ログの出力' 'title ending in a noun'
expect_rule no-pause-comma 'エラーの表示と、復旧までの手順' 'title with まで after the comma'
expect_rule no-pause-comma 'データの保存と、画面での表示' 'title with での after the comma'
expect_clean '設定の読み込みとログの出力' 'title without the comma'
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

# The line filters key on the path textlint reports, so run them for real.
printf 'これは革命的な技術です。\n\n設定を確かめる。\n' >"$workdir/edit.md"
edit_hook() {
  jq -cn --arg p "$workdir/edit.md" --argjson start "$1" \
    '{tool_name: "Edit", tool_input: {file_path: $p}, tool_response: {structuredPatch: [{newStart: $start, lines: $ARGS.positional}]}}' \
    --args "${@:2}" |
    XDG_CONFIG_HOME="$workdir" bash "$repo_root/.config/ai-writing/check-ai-writing.sh"
}
[ -z "$(edit_hook 3 '+設定を確かめる。')" ] || fail "hook should skip findings outside an Edit"
edit_hook 1 '+これは革命的な技術です。' | jq -e '.decision == "block"' >/dev/null ||
  fail "hook should block findings inside an Edit"

stop_repo="$workdir/stop-repo"
git init -q "$stop_repo"
printf '設定を確かめる。\n' >"$stop_repo/doc.md"
git -C "$stop_repo" add doc.md
git -C "$stop_repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -q -m doc
printf 'これは革命的な技術です。\n' >>"$stop_repo/doc.md"
stop_hook() {
  jq -cn --arg cwd "$stop_repo" '{session_id: "real", cwd: $cwd, stop_hook_active: false}' |
    XDG_CONFIG_HOME="$workdir" XDG_RUNTIME_DIR="$workdir/run" bash "$repo_root/.config/ai-writing/check-ai-writing.sh" "$1"
}
stop_hook --mark
sleep 1
printf '設定に、値を足す。\n' >>"$stop_repo/doc.md"
git -C "$stop_repo" add doc.md
git -C "$stop_repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -q -m turn
printf '設定を、直す。\n' >>"$stop_repo/doc.md"
stop_hook --stop | jq -e '.decision == "block" and (.reason | contains("line 3,") and contains("line 4,") and (contains("line 2,") | not))' >/dev/null ||
  fail "Stop should report the lines this turn added, committed or not, and skip earlier ones"

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

# Claude Code の記憶の索引は 1 行が `- [題](ファイル) — 説明` と決まっている
memory_index="$workdir/claude/projects/-home-user-repo/memory/MEMORY.md"
mkdir -p "${memory_index%/*}"
printf -- '- [設定の場所](setting.md) — 説明です\n' | tee "$memory_index" >"$workdir/memory-like.md"
memory_report=$(textlint --config "$config" --rulesdir "$repo_root/.config/ai-writing/rules" --format json "$memory_index" "$workdir/memory-like.md") || true
printf '%s' "$memory_report" | jq -e --arg index "$memory_index" '
  (.[] | select(.filePath == $index) | .messages | all(.ruleId != "no-prose-dash")) and
  (.[] | select(.filePath != $index) | .messages | any(.ruleId == "no-prose-dash"))' >/dev/null ||
  fail "no-prose-dash should skip only the memory index"

# The command line reports through the exit status.
cli_status=0
printf '設定に、値を足す。\n' |
  XDG_CONFIG_HOME="$workdir" bash "$repo_root/.config/ai-writing/check-ai-writing.sh" --stdin >"$workdir/cli-out" || cli_status=$?
[ "$cli_status" = 1 ] || fail "--stdin should exit 1 with findings"
grep -q '^stdin.md: line 1, .*(no-pause-comma)$' "$workdir/cli-out" ||
  fail "--stdin should report no-pause-comma"
printf '設定に値を足す。\n' |
  XDG_CONFIG_HOME="$workdir" bash "$repo_root/.config/ai-writing/check-ai-writing.sh" --stdin ||
  fail "--stdin should exit 0 for clean text"

config="$repo_root/.textlintrc-commit.json"
expect_rule terminology 'feat: update readme' 'README spelling'
expect_rule terminology 'feat: update readmes' 'READMEs spelling'
expect_clean 'feat: update README and READMEs' 'canonical README spelling'
run_cases

printf 'textlint configs: rule set, response and commit cases, and real hook verified\n'
