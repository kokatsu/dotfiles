#!/usr/bin/env bash
# AI writing check, shared by Claude Code and Codex hooks and the command line.
#
#   check-ai-writing.sh             PostToolUse hook. Claude Code's Edit/Write
#                                   pass tool_input.file_path, Codex's
#                                   apply_patch passes the patch in
#                                   tool_input.command.
#   check-ai-writing.sh --mark      UserPromptSubmit hook. Records when the
#                                   turn started and the uncommitted
#                                   documents at that point.
#   check-ai-writing.sh --stop      Stop hook. Lints the lines this turn added
#                                   to documents, which catches files
#                                   rewritten through Bash.
#   check-ai-writing.sh --files F…  Lints the given files.
#   check-ai-writing.sh --stdin     Lints standard input, such as a commit
#                                   message.
#
# Hook modes exit 0 and answer in JSON. --files and --stdin exit 0 without
# findings, 1 with findings and 2 when the check could not run.

set -uo pipefail

textlint_config="${XDG_CONFIG_HOME:-$HOME/.config}/ai-writing/textlint-response.json"
mark_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ai-writing"

usage() {
  echo 'Usage: check-ai-writing.sh [--files FILE... | --stdin | --stop | --mark]' >&2
  exit 2
}

is_document() {
  case "$1" in
  *.md | *.markdown | *.html | *.htm) return 0 ;;
  *) return 1 ;;
  esac
}

# Lints "$@" and sets lint_output. Returns 0 when clean, 1 with findings, and
# 2 with lint_error set when the check could not run.
lint() {
  local status=0 diagnostics
  if ! diagnostics=$(mktemp); then
    lint_error="AI 文体検査の一時ファイルを作成できませんでした。"
    return 2
  fi
  # textlint takes about 2.5 seconds to start, so every file goes to one
  # process to stay within the hook timeout.
  lint_output=$(
    textlint \
      --config "$textlint_config" \
      --rulesdir "${textlint_config%/*}/rules" \
      --format json \
      --no-color \
      -- "$@" 2>"$diagnostics"
  ) || status=$?
  # textlint returns 1 both for lint findings and for a config it cannot load,
  # so validate the report before requesting a rewrite.
  if [ "$status" -gt 1 ] || ! printf '%s' "$lint_output" | jq -e '
    type == "array" and length > 0 and all(.[];
      (.filePath | type == "string") and
      (.messages | type == "array" and all(.[];
        (.message | type == "string") and
        (.line | type == "number") and (.column | type == "number") and
        (.ruleId == null or (.ruleId | type == "string")))))
  ' >/dev/null 2>&1 || { [ "$status" -eq 1 ] && ! printf '%s' "$lint_output" | jq -e 'any(.[]; .messages | length > 0)' >/dev/null; }; then
    lint_error="AI 文体検査を実行できませんでした (textlint の終了コード: ${status}、設定: ${textlint_config})
$lint_output
$(cat "$diagnostics")"
    rm -f "$diagnostics"
    return 2
  fi
  rm -f "$diagnostics"
  return "$status"
}

# Prints one line per finding in lint_output. $1 maps a file path to the
# [first, last] line ranges to report; a file it leaves out is reported whole.
findings() {
  printf '%s' "$lint_output" | jq -r --argjson ranges "$1" '
    .[] as $file | $ranges[$file.filePath] as $r
    | $file.messages[] | . as $m
    | select($r == null or any($r[]; .[0] <= $m.line and $m.line <= .[1]))
    | "\($file.filePath): line \(.line), col \(.column), \(.message) (\(.ruleId // "textlint"))"'
}

# Lints "$@" and answers a hook in JSON: a block with $2 as the instruction,
# or a systemMessage when the check could not run.
answer_hook() {
  local ranges=$1 instruction=$2 status=0 found
  shift 2
  lint "$@" || status=$?
  if [ "$status" -eq 2 ]; then
    jq -n --arg message "$lint_error" '{systemMessage: $message}'
    return
  fi
  [ "$status" -eq 1 ] || return
  found=$(findings "$ranges")
  [ -n "$found" ] || return
  jq -n --arg reason "$instruction

$found" '{decision: "block", reason: $reason}'
}

post_tool_use() {
  local payload paths cwd file_path ranges='{}' files=()
  payload=$(cat || true)
  if ! paths=$(printf '%s' "$payload" | jq -r '
    if .tool_input.file_path then .tool_input.file_path
    elif .tool_name == "apply_patch" then
      .tool_input.command // "" | split("\n")[]
      | capture("^\\s*\\*\\*\\* (Add File|Update File|Move to): (?<path>.*\\S)").path?
    else empty end' 2>/dev/null); then
    jq -n --arg message "AI 文体検査の hook 入力が不正な JSON でした。検査をスキップします。" '{systemMessage: $message}'
    return
  fi
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')

  while IFS= read -r file_path; do
    is_document "$file_path" || continue
    case "$file_path" in
    /*) ;;
    *) file_path="$cwd/$file_path" ;;
    esac
    # An Update File followed by Move to names a path that no longer exists.
    [ -f "$file_path" ] || continue
    # textlint reports the path resolved, and the Edit ranges key on it.
    file_path="$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path")" &&
      files+=("$file_path")
  done <<<"$paths"
  [ "${#files[@]}" -gt 0 ] || return

  # An Edit reports only the lines its patch added.
  if printf '%s' "$payload" | jq -e '.tool_name == "Edit" and (.tool_response.structuredPatch | type == "array")' >/dev/null 2>&1; then
    ranges=$(printf '%s' "$payload" | jq -c --arg f "${files[0]}" '
      {($f): [.tool_response.structuredPatch[] | foreach .lines[] as $line
        ({n: .newStart};
          if $line | startswith("+") then .added = .n | .n += 1
          elif $line | startswith(" ") then .added = null | .n += 1
          else .added = null end;
          .added | values | [., .])]}')
  fi
  answer_hook "$ranges" "書き込んだファイルに AI 文体のパターンが検出されました。書き込み自体は完了しています。指摘された行だけを自然で簡潔な文章に直してください。指摘箇所以外の内容は変更しないでください。" "${files[@]}"
}

session_mark() {
  printf '%s' "$1" | jq -r '.session_id // empty | select(test("^[A-Za-z0-9_-]+$"))' 2>/dev/null
}

repo_root() {
  git -C "$(printf '%s' "$1" | jq -r '.cwd // "."')" rev-parse --show-toplevel 2>/dev/null
}

# Lists the documents in $1 that differ from commit $2, or every document
# when $2 is empty, including deleted ones.
changed_documents() {
  local file
  while IFS= read -r -d '' file; do
    is_document "$file" && printf '%s\0' "$file"
  done < <(
    if [ -n "$2" ]; then
      git -C "$1" diff "$2" --name-only --no-renames -z
    else
      git -C "$1" ls-files --cached -z
    fi
    git -C "$1" ls-files --others --exclude-standard -z
  )
}

# Records the repository and HEAD and snapshots the documents that differ from it, so that
# --stop can tell the lines this turn added from earlier ones, even after a
# commit in the turn. The snapshot copies uncommitted work, so only the user
# may read it.
mark() {
  local payload session snapshot root head='' file
  umask 077
  payload=$(cat || true)
  session=$(session_mark "$payload")
  [ -n "$session" ] || return
  snapshot="$mark_dir/$session"
  rm -rf "$snapshot" "$snapshot.mark" && mkdir -p "$snapshot/files" "$snapshot/deleted" || return
  root=$(repo_root "$payload") || return
  head=$(git -C "$root" rev-parse --verify -q HEAD)
  printf '%s\n' "$root" "$head" >"$snapshot.mark"
  # A deleted document is recorded in its own tree, since its path may now be
  # a directory of documents. Restoring it counts as adding every line.
  while IFS= read -r -d '' file; do
    if [ -f "$root/$file" ]; then
      mkdir -p "$(dirname "$snapshot/files/$file")" && cp "$root/$file" "$snapshot/files/$file"
    else
      mkdir -p "$(dirname "$snapshot/deleted/$file")" && : >"$snapshot/deleted/$file"
    fi
  done < <(changed_documents "$root" "$head")
}

# Files ignored by Git are left out: they are generated or vendored, and an
# Edit or Write to one is still checked by post_tool_use.
stop() {
  local payload session snapshot root head file base head_copy hunks ranges='{}' files=()
  payload=$(cat || true)
  printf '%s' "$payload" | jq -e '.stop_hook_active == true' >/dev/null 2>&1 && return
  session=$(session_mark "$payload")
  snapshot="$mark_dir/$session"
  [ -n "$session" ] && [ -f "$snapshot.mark" ] || return
  # The cwd may have moved to another repository since the mark.
  { IFS= read -r root && read -r head; } <"$snapshot.mark" || return
  head_copy=$(mktemp) || return

  while IFS= read -r -d '' file; do
    # A document absent from the snapshot matched the recorded HEAD.
    if [ -f "$snapshot/files/$file" ]; then
      base="$snapshot/files/$file"
    elif [ -f "$snapshot/deleted/$file" ]; then
      base=/dev/null
    elif [ -n "$head" ] && git -C "$root" show "$head:$file" >"$head_copy" 2>/dev/null; then
      base=$head_copy
    else
      base=/dev/null
    fi
    [ -f "$root/$file" ] || continue
    cmp -s "$base" "$root/$file" && continue
    files+=("$root/$file")
    # A hunk header +START,COUNT omits COUNT when it is 1 and gives 0 for a
    # pure deletion.
    hunks=$(git diff --no-index -U0 --no-color --no-ext-diff -- "$base" "$root/$file" |
      sed -n 's/^@@ -[0-9,]* +\([0-9]*\)\(,\([0-9]*\)\)\{0,1\} @@.*/\1 \3/p')
    ranges=$(printf '%s\n' "$hunks" | jq -cRn --arg f "$root/$file" --argjson ranges "$ranges" '
      [inputs | select(. != "") | split(" ") | (.[0] | tonumber) as $start
        | (if .[1] == "" then 1 else .[1] | tonumber end) as $count
        | select($count > 0) | [$start, $start + $count - 1]]
      | $ranges + {($f): .}')
  done < <(
    # A snapshotted document the turn reverted to HEAD still differs from
    # the snapshot.
    {
      changed_documents "$root" "$head"
      while IFS= read -r -d '' file; do
        printf '%s\0' "${file#*/}"
      done < <(cd "$snapshot" && find files deleted -type f -print0)
    } | sort -zu
  )
  rm -f "$head_copy"
  [ "${#files[@]}" -gt 0 ] || return

  answer_hook "$ranges" "このターンで変更したファイルに AI 文体のパターンが検出されました。指摘された行だけを自然で簡潔な文章に直してください。指摘箇所以外の内容は変更しないでください。" "${files[@]}"
}

# Prints the findings for a person and exits 0, 1 or 2.
report() {
  local status=0
  lint "$@" || status=$?
  if [ "$status" -eq 2 ]; then
    printf '%s\n' "$lint_error" >&2
    exit 2
  fi
  [ "$status" -eq 0 ] || findings '{}'
  exit "$status"
}

case "${1:-}" in
--files)
  shift
  [ "$#" -gt 0 ] || usage
  report "$@"
  ;;
--stdin)
  [ "$#" -eq 1 ] || usage
  stdin_dir=$(mktemp -d) || exit 2
  trap 'rm -rf "$stdin_dir"' EXIT
  cat >"$stdin_dir/stdin.md"
  report "$stdin_dir/stdin.md" | sed "s|^$stdin_dir/||"
  exit "${PIPESTATUS[0]}"
  ;;
--stop) stop ;;
--mark) mark ;;
'')
  [ -t 0 ] && usage
  post_tool_use
  ;;
*) usage ;;
esac
exit 0
