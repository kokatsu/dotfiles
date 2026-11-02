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

# ------------------------------------------------------------------------------
# Ghostty Shell Integration
# ------------------------------------------------------------------------------

if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
  local _gi="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
  [[ -f "$_gi" ]] && source "$_gi"
  unset _gi
fi

