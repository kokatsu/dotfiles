# ------------------------------------------------------------------------------
# Claude Code (https://github.com/anthropics/claude-code)
# ------------------------------------------------------------------------------

# 注: 同じ OSC 1337 構築を .config/claude/hooks/notify.sh が複製（手動同期）
function _wezterm_set_user_var() {
  printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$(printf '%s' "$2" | base64)"
}

# IS_CLAUDE user varでWezTermのマウス動作を切り替え
# (herdr 配下ではマウスは herdr が処理するため実質 no-op、生シェルでは従来通り)
function claude() {
  if [[ $# -gt 0 ]]; then
    command claude "$@"
  else
    _wezterm_set_user_var IS_CLAUDE 1
    command claude
    _wezterm_set_user_var IS_CLAUDE 0
  fi
}

# ------------------------------------------------------------------------------
# herdr (https://herdr.dev)
# ------------------------------------------------------------------------------

# クライアント起動だけ HERDR_CLIENT user var を立てるラッパーを通す
function herdr() {
  if [[ $# -gt 0 ]]; then
    command herdr "$@"
  else
    "$HOME/.config/herdr/scripts/herdr-client.sh"
  fi
}

# ------------------------------------------------------------------------------
# Yazi (https://github.com/sxyazi/yazi)
# ------------------------------------------------------------------------------

# https://yazi-rs.github.io/docs/quick-start/#shell-wrapper
function yi() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# ------------------------------------------------------------------------------
# Helix (https://helix-editor.com)
# ------------------------------------------------------------------------------

# 引数なし・ディレクトリ 1 つのときは Yazi で選んだファイルを開く。
# hx はディレクトリ引数で組み込みの file picker を開き、設定では差し替えられない。
function hx() {
  if [[ $# -gt 1 || ( $# -eq 1 && ! -d $1 ) ]]; then
    command hx "$@"
    return
  fi
  local tmp="$(mktemp -t "yazi-chooser.XXXXXX")"
  yazi "${1:-.}" --chooser-file="$tmp"
  local -a files=(${(f)"$(command cat -- "$tmp")"})
  rm -f -- "$tmp"
  (( $#files )) && command hx -- "${files[@]}"
}

# ------------------------------------------------------------------------------
# Pkl (https://pkl-lang.org)
# ------------------------------------------------------------------------------

# .pkl を JSON / YAML へ変換し、入力と同じ場所に <basename>.json / .yaml を書き出す
# 例: pkl2json config.pkl       → config.json を作成/更新
#     pkl2yaml a.pkl b.pkl      → a.yaml, b.yaml を一括変換
#     pkl2json -o out.json a.pkl → -o 等の出力指定があれば pkl eval にそのまま委譲

function pkl2json() {
  _pkl_convert json "$@"
}

function pkl2yaml() {
  _pkl_convert yaml "$@"
}

# 内部: $1=フォーマット (拡張子兼用), 残りはユーザー引数
function _pkl_convert() {
  emulate -L zsh
  local fmt=$1
  shift

  if (( $# == 0 )); then
    print -u2 "usage: pkl2${fmt} [-o <out>] <file.pkl> [more.pkl ...]"
    return 2
  fi

  local arg
  for arg in "$@"; do
    case $arg in
      -o|--output-path|--output-path=*|-m|--multiple-file-output-path|--multiple-file-output-path=*)
        command pkl eval -f "$fmt" "$@"
        return
        ;;
    esac
  done

  local f out rc=0
  for f in "$@"; do
    if [[ ! -f $f ]]; then
      print -u2 "pkl2${fmt}: not a file: $f"
      rc=1
      continue
    fi
    out=${f%.pkl}.${fmt}
    command pkl eval -f "$fmt" -o "$out" "$f" || rc=$?
  done
  return $rc
}
