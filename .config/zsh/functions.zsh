# ------------------------------------------------------------------------------
# Claude Code (https://github.com/anthropics/claude-code)
# ------------------------------------------------------------------------------

# WezTerm User Variable を設定（OSC 1337）
# tmux内の場合はDCSパススルーでWezTermに転送
# 注: 同じ OSC 1337 構築を .config/claude/hooks/notify.sh が複製（手動同期）
function _wezterm_set_user_var() {
  if [[ -n "$TMUX" ]]; then
    printf "\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\" "$1" "$(printf '%s' "$2" | base64)"
  else
    printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$(printf '%s' "$2" | base64)"
  fi
}

# Claude Code を起動
# マルチプレクサは herdr が常時ハブ (WezTerm gui-startup で自動起動) のため
# tmux セッションの自動生成はせず常に直接実行する
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
# ripgrep (https://github.com/BurntSushi/ripgrep)
# ------------------------------------------------------------------------------

# パス順にソートして検索する。--sort は常に単一スレッド実行になるため
# ~/.config/.ripgreprc には入れず、目視で読みたいときだけこちらを使う。
function rgs() {
  command rg --sort=path "$@"
}

# ------------------------------------------------------------------------------
# curl
# ------------------------------------------------------------------------------

# Bearer Token を非表示で読み取り、コマンド履歴と curl の引数に載せずに渡す。
# 例: curl-bearer https://api.example.com/resource
#     curl-bearer -X POST --json '{"name":"example"}' https://api.example.com/resource
function curl-bearer() {
  emulate -L zsh
  unsetopt xtrace

  if (( $# == 0 )); then
    print -u2 'usage: curl-bearer [curl options] <url>'
    return 2
  fi

  local token rc tty_fd
  if ! { exec {tty_fd}</dev/tty } 2>/dev/null; then
    print -u2 'curl-bearer: cannot read token from /dev/tty'
    return 1
  fi

  local read_rc
  {
    read -rs 'token?Bearer Token (input hidden): ' <&$tty_fd
    read_rc=$?
  } always {
    exec {tty_fd}<&-
  }

  if (( read_rc != 0 )); then
    print -u2
    print -u2 'curl-bearer: failed to read token'
    return 1
  fi
  print -u2

  if [[ -z $token ]]; then
    print -u2 'curl-bearer: token must not be empty'
    return 2
  fi
  print -u2 'curl-bearer: ✓ Bearer Token received'

  # process substitution でヘッダーだけを別ファイルディスクリプタから渡し、
  # curl の標準入力は --data-binary @- 等に使える状態を保つ。
  command curl --header @<(print -r -- "Authorization: Bearer $token") "$@"
  rc=$?
  return $rc
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

  # 出力指定フラグがあれば pkl eval にそのまま渡す
  local arg
  for arg in "$@"; do
    case $arg in
      -o|--output-path|--output-path=*|-m|--multiple-file-output-path|--multiple-file-output-path=*)
        command pkl eval -f "$fmt" "$@"
        return
        ;;
    esac
  done

  # デフォルト: 各入力の隣に <basename>.<fmt> を生成 (.pkl は除去)
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
