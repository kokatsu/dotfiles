# ------------------------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------------------------

_evalcache /home/linuxbrew/.linuxbrew/bin/brew shellenv

# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------

alias c="clear && fastfetch"

# ------------------------------------------------------------------------------
# WSL
# ------------------------------------------------------------------------------

if grep -q -e Microsoft -e microsoft /proc/version; then
  alias copy="iconv -f utf-8 -t utf-16le | clip.exe"
fi

# https://github.com/wezterm/wezterm/issues/5503
# https://github.com/wezterm/wezterm/issues/5503#issuecomment-2600490028
precmd_wsl() {
  if grep -q -e Microsoft -e microsoft /proc/version; then
    printf "\033]7;file://%s%s\033\\" "${HOSTNAME}" "${PWD}"
  fi
}

autoload -U add-zsh-hook
add-zsh-hook precmd precmd_wsl
