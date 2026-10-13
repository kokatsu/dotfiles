#!/bin/bash
# 起動元ペインの Claude Code / Codex の応答に出たパスを fzf で選び、Neovim で開く。
# 画面上で折り返されたパスは WezTerm のクリックでは断片しか拾えないため、
# 折り返す前の文章が残っている会話ログから拾う。
# Enter: Neovim で開く / Ctrl-y: パスをクリップボードへコピー
#
#   pick-agent-path.sh --list <claude|codex> <ログ>
#     実在するパスを新しい応答から順に "<絶対パス>\t<行>\t<表示名>" で出力する (行はない場合は空)

set -euo pipefail

# 応答 1 つの文章から候補を拾う。Markdown リンクはリンク先だけを取り、表示名は拾わない
# (表示名の app.py:7 が cwd の別の app.py に当たるため)。/ も拡張子もない名前
# (justfile など) は、地の文の単語が同名のディレクトリに当たらないよう、
# バッククォート内に限って拾う。
# 地の文のパスは日本語を含みうるので、空白と区切り記号までをひとまとめに取る。
# 文字種で切ると src/日本語.ts の src/ のような断片が実在チェックを通ってしまう。
# 後ろに続く助詞 (foo.sh を の「を」) は、外した残りが拡張子か行番号で終わるときだけ外す。
# 強調の * は前後だけ外す。区切り文字にすると lib/*.ts が lib/ の断片になる
# shellcheck disable=SC2016
candidates='
def link: "\\[[^\\]\\n]*\\]\\((?:<([^>\\n]+)>|([^)\\s]+))\\)";
def token: "[^\\s`\"'"'"'()<>\\[\\]{},;|、。，．「」『』（）【】]+";
def ext: "\\.[A-Za-z0-9]+(?::[0-9]+(?:-[0-9]+)?){0,2}$";
def trim_tail: sub("(?:[.:*]|[^\\x00-\\x7F])+$"; "") as $t | if $t | test(ext) then $t else . end;
. as $text
| ($text | gsub(link; " ")) as $rest
| [
  ($text | scan(link) | .[0] // .[1]),
  ($rest | scan("`(" + token + ")`") | .[0]),
  ($rest | scan(token) | select(contains("/") or contains(".")) | sub("^\\*+"; "") | sub("\\*+$"; "") | trim_tail | sub("[.:]+$"; "") | select(test("/") or test(ext)))
]
| .[]
| capture("^(?<path>.+?)(?::(?<line>[0-9]+)(?:-[0-9]+)?)?(?::[0-9]+)?$")
| select(.path | test("[^/.~]"))'

# shellcheck disable=SC2016
list_paths() {
  local agent=$1 log=$2 responses
  # 応答ごとに [cwd, 文章] を古い順に出す。書き込み途中の行で全体が止まらないよう、
  # JSON として読めない行は飛ばす
  case "$agent" in
  claude)
    responses='inputs | fromjson? // empty
      | select(.type == "assistant" and (.isSidechain | not) and (.isApiErrorMessage | not))
      | .cwd as $cwd | .message.content[]? | select(.type == "text") | [$cwd, .text]'
    ;;
  codex)
    # Codex は cwd を先頭の session_meta にしか持たない
    responses='reduce (inputs | fromjson? // empty) as $r ({cwd: null, out: []};
      if $r.type == "session_meta" then .cwd = $r.payload.cwd
      elif $r.type == "response_item" and $r.payload.role == "assistant" then
        .cwd as $cwd
        | .out += [$r.payload.content[]? | select(.type == "output_text") | [$cwd, .text]]
      else . end) | .out[]'
    ;;
  *) return 1 ;;
  esac
  local cwd path line abs display
  jq -nrR "def cands: $candidates; [$responses] | reverse[]"'
    | .[0] as $cwd | .[1] | cands | [$cwd, .path, (.line // "")] | join("\u001f")' "$log" |
    awk '!seen[$0]++' |
    # TAB は IFS で連続が 1 つにまとまり、空の列が消えるので、空白でない区切りを使う
    while IFS=$'\x1f' read -r cwd path line; do
      case "$path" in
      /*) abs=$path ;;
      "~"/*) abs=$HOME/${path#"~/"} ;;
      *) abs=${cwd%/}/${path#./} ;;
      esac
      [[ -e "$abs" ]] || continue
      display=${abs#"${cwd%/}"/}
      display=${display/#"$HOME"/"~"}
      printf '%s\t%s\t%s\n' "$abs" "$line" "$display${line:+:$line}"
    done |
    awk -F'\t' '!seen[$1 FS $2]++'
}

case "${1:-}" in
--list)
  list_paths "$2" "$3"
  exit
  ;;
--preview)
  if [[ -d "$2" ]]; then
    eza --tree --level=2 --color=always "$2"
  elif [[ -n "$3" ]]; then
    bat --color=always --style=numbers --highlight-line "$3" \
      --line-range "$((${3} > 10 ? ${3} - 10 : 1)):" "$2"
  else
    bat --color=always --style=numbers "$2"
  fi
  exit
  ;;
esac

# shellcheck source=.config/herdr/scripts/lib.sh
source "$(dirname "$0")/lib.sh"
active_pane_id=${HERDR_ACTIVE_PANE_ID:?HERDR_ACTIVE_PANE_ID is not set}

# popup はスクリプトの終了と同時に閉じ、herdr の通知だけでは閉じた理由を見落とすので、
# 理由を popup に出してキー入力を待つ
explain() {
  printf '%s\n' "$@"
  printf '\n何かキーを押すと閉じます'
  read -rsn1 || true
  exit 0
}

# Codex のセッションを、ペインのタイトル (tui.terminal_title の thread) と同じ名前の
# スレッドから探し、"<ログ>\t<更新日時>\t<スレッド名>" で出力する。herdr の agent_session は
# 使えない。共有 app-server daemon の中で動くフックからは、セッションを始めたペインを
# 特定できないため。名前は一意でないので、ログの cwd がペインの cwd と同じものに絞る。
# 省略されたタイトル (末尾が ...) は前方一致で比べる
codex_logs() {
  local title=$1 cwd=$2 codex_home=${CODEX_HOME:-$HOME/.codex} id updated name log
  [[ -n "$title" && -f "$codex_home/session_index.jsonl" ]] || return 0
  jq -nrR --arg title "$title" '
    reduce (inputs | fromjson? // empty) as $r ({}; .[$r.id] = $r) | .[]
    | select(.thread_name == $title or
        ($title | test("(\\.\\.\\.|…)$")) and
        (.thread_name | startswith($title | sub("(\\.\\.\\.|…)$"; ""))))
    | [.id, .updated_at, .thread_name] | @tsv' "$codex_home/session_index.jsonl" |
    while IFS=$'\t' read -r id updated name; do
      for log in "$codex_home"/sessions/*/*/*/rollout-*-"$id".jsonl; do
        if [[ $(jq -nrR 'first(inputs | fromjson? // empty | select(.type == "session_meta") | .payload.cwd)' "$log") == "$cwd" ]]; then
          printf '%s\t%s\t%s\n' "$log" "$updated" "$name"
        fi
      done
    done
}

pane=$("$herdr_bin" pane get "$active_pane_id") || pane='{}'
agent=$(jq -r '.result.pane.agent // ""' <<<"$pane")
shopt -s nullglob
case "$agent" in
claude)
  # agent_session は SessionStart フック (tools/agent-hooks/report-agent-session) が報告する
  session_id=$(jq -r '.result.pane.agent_session.value // ""' <<<"$pane")
  logs=()
  [[ -n "$session_id" ]] && logs=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$session_id".jsonl)
  if ((${#logs[@]} == 0)); then
    explain "セッションの会話ログが見つかりません" "session: ${session_id:-(herdr に未報告)}"
  fi
  log=${logs[0]}
  ;;
codex)
  title=$(jq -r '.result.pane.terminal_title_stripped // ""' <<<"$pane")
  cwd=$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd // ""' <<<"$pane")
  sessions=$(codex_logs "$title" "$cwd" | sort -t $'\t' -k2,2r)
  if [[ -z "$sessions" ]]; then
    explain "タイトルと同じ名前の Codex のセッションが見つかりません" "title: ${title:-(なし)}" "cwd: $cwd"
  fi
  log=${sessions%%$'\t'*}
  if [[ "$sessions" == *$'\n'* ]]; then
    log=$(fzf --delimiter '\t' --with-nth 2,3 --no-sort \
      --header '同じ名前のセッションが複数あります' <<<"$sessions") || true
    log=${log%%$'\t'*}
    [[ -z "$log" ]] && exit 0
  fi
  ;;
*)
  explain "Claude Code / Codex のペインではありません"
  ;;
esac

paths=$(list_paths "$agent" "$log")
if [[ -z "$paths" ]]; then
  explain "応答に実在するパスがありません" "log: $log"
fi

# fzf のキャンセル (exit 130) を set -e で落とさず、空選択として扱う
self=$(printf '%q' "$0")
out=$(fzf --delimiter '\t' --with-nth 3 --no-sort --expect ctrl-y \
  --header 'Enter: Neovim で開く / Ctrl-y: コピー' \
  --preview "$self --preview {1} {2}" \
  --preview-window=right:60% <<<"$paths") || true
key=$(head -n 1 <<<"$out")
chosen=$(sed -n 2p <<<"$out")
[[ -z "$chosen" ]] && exit 0
# 行が空のとき、IFS の TAB は連続を 1 つにまとめて列がずれるので read で分けない
abs=${chosen%%$'\t'*}
line=${chosen#*$'\t'}
line=${line%%$'\t'*}

if [[ "$key" == ctrl-y ]]; then
  printf '%s' "$abs${line:+:$line}" | copy_to_clipboard
  notify "パスをコピーしました" "$abs"
  exit 0
fi

open_in_nvim="$(dirname "$0")/open-in-nvim.sh"
result=$(bash "$open_in_nvim" --existing-only "$abs" "$line") && exit 0
# 1 行目は "<絶対パス>\t<cwd>\t<workspace>"。--server と --new-tab は cwd と workspace を
# 取り直さず、ここで渡した値でタブを作る
IFS=$'\t' read -r abs cwd workspace <<<"$(head -n 1 <<<"$result")"
if [[ -z "${workspace:-}" ]]; then
  notify "Neovim で開けませんでした" "$abs"
  exit 1
fi
target=new-tab
sockets=$(tail -n +2 <<<"$result")
if [[ -n "$sockets" ]]; then
  target=$({
    printf 'new-tab\t新規タブで開く\n'
    printf '%s\n' "$sockets"
  } | fzf --delimiter '\t' --with-nth 2 --no-sort \
    --header '同じタブに nvim が複数あります') || true
  target=${target%%$'\t'*}
  [[ -z "$target" ]] && exit 0
fi
if [[ "$target" == new-tab ]]; then
  args=(--new-tab)
else
  args=(--server "$target")
fi
exec bash "$open_in_nvim" "${args[@]}" --cwd "$cwd" --workspace "$workspace" "$abs" "$line"
