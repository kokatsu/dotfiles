# ------------------------------------------------------------------------------
# Claude Code (https://github.com/anthropics/claude-code)
# ------------------------------------------------------------------------------

# WezTerm User Variable を設定（OSC 1337）
# tmux内の場合はDCSパススルーでWezTermに転送
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
    _wezterm_set_user_var IS_CLAUDE 1
    tmux new-session -A -s "$session_name" "command claude"
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
