# ------------------------------------------------------------------------------
# WSL Detection (cached)
# ------------------------------------------------------------------------------

if [[ -f /proc/version ]] && read -r _v < /proc/version && [[ "$_v" == *[Mm]icrosoft* ]]; then
  _IS_WSL=1
else
  _IS_WSL=0
fi

# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------

alias c="clear && fastfetch"

# ------------------------------------------------------------------------------
# WSL
# ------------------------------------------------------------------------------

if (( _IS_WSL )); then
  alias copy="iconv -f utf-8 -t utf-16le | clip.exe"
  export BROWSER="wslview"

  # https://blog.adglobe.co.jp/entry/2024/07/31/100000
  if [[ ! -f /tmp/.mtu_1400_set ]]; then
    if [[ $(ip link show eth0 2>/dev/null | grep -o 'mtu [0-9]*' | awk '{print $2}') != "1400" ]]; then
      sudo ip link set eth0 mtu 1400 2>/dev/null && touch /tmp/.mtu_1400_set
    else
      touch /tmp/.mtu_1400_set
    fi
  fi
fi

# https://github.com/wezterm/wezterm/issues/5503
# https://github.com/wezterm/wezterm/issues/5503#issuecomment-2600490028
precmd_wsl() {
  if (( _IS_WSL )); then
    printf "\033]7;file://%s%s\033\\" "${HOSTNAME}" "${PWD}"
  fi
}

autoload -U add-zsh-hook
add-zsh-hook precmd precmd_wsl
