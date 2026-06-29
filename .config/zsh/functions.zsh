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

# Claude Codeをtmux内で起動
# 引数がある場合: 直接実行（--version等のオプション用）
# tmux/cmux内の場合: 直接実行（多重化不要）
# それ以外: tmuxセッションを作成してclaude起動
#   - WEZTERM_PANE がある場合: ペインごとに独立したセッション
#   - それ以外: 共有セッション 'claude'
# IS_CLAUDE user varでWezTermのマウス動作を切り替え
function claude() {
  if [[ $# -gt 0 ]]; then
    command claude "$@"
  elif [[ -n "$TMUX" ]] || [[ -n "$CMUX_SURFACE_ID" ]]; then
    _wezterm_set_user_var IS_CLAUDE 1
    command claude
    _wezterm_set_user_var IS_CLAUDE 0
  else
    local session_name="claude${WEZTERM_PANE:+-$WEZTERM_PANE}"
    # ウィンドウ名にバージョンのみを表示（automatic-rename は -n 指定で off になる）
    local version="$(command claude --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    _wezterm_set_user_var IS_CLAUDE 1
    # TMUX を空にして CC の tmux 検出を回避（薄palette回避）
    # 通知は notify.sh が CC 本体の pts に DCS passthrough を直書きするので
    # CC 自身の tmux 検出は不要
    tmux new-session -A -s "$session_name" -n "$version" \
      "TMUX= command claude"
    _wezterm_set_user_var IS_CLAUDE 0
  fi
}

# ------------------------------------------------------------------------------
# Codex CLI (https://github.com/openai/codex)
# ------------------------------------------------------------------------------

# Codex CLIをtmux内で起動 (claude() と同じ要領)
# tmux 内で動かす理由: tmux の Alt+c / Alt+g キーバインドから
# codex-path-pick-{fzf,broot}.sh を display-popup で起動するため
# 引数がある場合: 直接実行（--version 等のオプション用）
# tmux/cmux内の場合: 直接実行（多重化不要）
# それ以外: tmuxセッションを作成して codex 起動
#   - WEZTERM_PANE がある場合: ペインごとに独立したセッション
#   - それ以外: 共有セッション 'codex'
function codex() {
  if [[ $# -gt 0 ]]; then
    command codex "$@"
  elif [[ -n "$TMUX" ]] || [[ -n "$CMUX_SURFACE_ID" ]]; then
    command codex
  else
    local session_name="codex${WEZTERM_PANE:+-$WEZTERM_PANE}"
    # ウィンドウ名にバージョンのみを表示（automatic-rename は -n 指定で off になる）
    local version="$(command codex --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    tmux new-session -A -s "$session_name" -n "$version" \
      "TMUX= command codex"
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
