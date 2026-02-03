# ------------------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------------------

_evalcache /opt/homebrew/bin/brew shellenv

# ------------------------------------------------------------------------------
# Keybindings (WezTerm用)
# ------------------------------------------------------------------------------

# Option + 左右矢印で単語移動 (CSIシーケンス)
bindkey -M viins '^[[1;3D' backward-word
bindkey -M viins '^[[1;3C' forward-word
bindkey -M vicmd '^[[1;3D' backward-word
bindkey -M vicmd '^[[1;3C' forward-word

# Control + 左右矢印で単語移動
bindkey -M viins '^[[1;5D' backward-word
bindkey -M viins '^[[1;5C' forward-word
bindkey -M vicmd '^[[1;5D' backward-word
bindkey -M vicmd '^[[1;5C' forward-word

# Option + Backspaceで単語削除
bindkey -M viins '^W' backward-kill-word

# ------------------------------------------------------------------------------
# Ghostty Shell Integration
# ------------------------------------------------------------------------------

if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
    source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi

# ------------------------------------------------------------------------------
# Nix
# ------------------------------------------------------------------------------

alias rebuild='sudo HOSTNAME=$(hostname -s) darwin-rebuild switch --flake ~/workspace/dotfiles --impure'
