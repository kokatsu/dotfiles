# ------------------------------------------------------------------------------
# Alias
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# bat (https://github.com/sharkdp/bat)
# ------------------------------------------------------------------------------

alias bag="bat --style grid"

# ------------------------------------------------------------------------------
# fd (https://github.com/sharkdp/fd)
# ------------------------------------------------------------------------------

alias fd="fd --hidden"

# ------------------------------------------------------------------------------
# eza (https://github.com/eza-community/eza)
# ------------------------------------------------------------------------------

alias e="eza --icons --git"
alias ea="eza -a --icons --git"
alias ee="eza -aahl --icons --git"

# ------------------------------------------------------------------------------
# Lazydocker (https://github.com/jesseduffield/lazydocker)
# ------------------------------------------------------------------------------

alias lzd="lazydocker"

# ------------------------------------------------------------------------------
# git-graph (https://github.com/mlange-42/git-graph)
# Requires: https://github.com/kokatsu/git-graph/tree/feat/current-option
# ------------------------------------------------------------------------------

alias gg="git-graph --model catppuccin-mocha --style bold --color always --current --max-count 50 --format '%H%d %s' --highlight-head 'bold,black,bg:bright_yellow'"

# ------------------------------------------------------------------------------
# Lazygit (https://github.com/jesseduffield/lazygit)
# ------------------------------------------------------------------------------

alias lg="lazygit"

# ------------------------------------------------------------------------------
# Neovim (https://github.com/neovim/neovim)
# ------------------------------------------------------------------------------

alias vi="nvim"

# ------------------------------------------------------------------------------
# spotify-player (https://github.com/aome510/spotify-player)
# ------------------------------------------------------------------------------

alias sp="spotify_player"

# ------------------------------------------------------------------------------
# Claude Code (https://github.com/anthropics/claude-code)
# ------------------------------------------------------------------------------

# WezTerm User Variable を設定（OSC 1337）
# tmux内の場合はDCSパススルーでWezTermに転送
_wezterm_set_user_var() {
  if [[ -n "$TMUX" ]]; then
    printf "\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\" "$1" "$(printf '%s' "$2" | base64)"
  else
    printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$(printf '%s' "$2" | base64)"
  fi
}

# Claude Codeをtmux内で起動
# 引数がある場合: 直接実行（--version等のオプション用）
# tmux内の場合: claude-chill経由で起動（差分描画で高速化）
# tmux外で引数なしの場合: tmuxセッションを作成してclaude起動
#   - WEZTERM_PANE がある場合: ペインごとに独立したセッション
#   - それ以外: 共有セッション 'claude'
# IS_CLAUDE user varでWezTermのマウス動作を切り替え
claude() {
  if [[ $# -gt 0 ]]; then
    command claude "$@"
  elif [[ -n "$TMUX" ]]; then
    _wezterm_set_user_var IS_CLAUDE 1
    command claude
    # command claude-chill claude
    _wezterm_set_user_var IS_CLAUDE 0
  else
    local session_name="claude${WEZTERM_PANE:+-$WEZTERM_PANE}"
    _wezterm_set_user_var IS_CLAUDE 1
    tmux new-session -A -s "$session_name" "command claude"
    # tmux new-session -A -s "$session_name" "command claude-chill claude"
    _wezterm_set_user_var IS_CLAUDE 0
  fi
}
