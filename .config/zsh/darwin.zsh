# ------------------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------------------

_evalcache /opt/homebrew/bin/brew shellenv

# ------------------------------------------------------------------------------
# Keybindings (WezTerm用)
# ------------------------------------------------------------------------------

# Option + 左右矢印で単語移動 (CSIシーケンス)
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word

# Control + 左右矢印で単語移動
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

# Option + Backspaceで単語削除
bindkey '^W' backward-kill-word

# ------------------------------------------------------------------------------
# Ghostty Shell Integration
# ------------------------------------------------------------------------------

if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
  local _gi="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
  # cmux はパス構造が異なる
  [[ -f "$_gi" ]] || _gi="${GHOSTTY_RESOURCES_DIR:h}/shell-integration/ghostty-integration.zsh"
  [[ -f "$_gi" ]] && source "$_gi"
  unset _gi
fi

