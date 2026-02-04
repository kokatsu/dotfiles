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

# Claude Codeをtmux内で起動
# tmux外の場合: tmuxセッション 'claude' を作成/アタッチしてclaude起動
# tmux内の場合: 直接claude起動（command で元のバイナリを呼び出し）
alias claude='if [ -n "$TMUX" ]; then command claude; else tmux new-session -A -s claude "command claude"; fi'
