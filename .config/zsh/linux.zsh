# ------------------------------------------------------------------------------
# WSL Detection (cached)
# ------------------------------------------------------------------------------

if [[ -f /proc/version ]] && read -r _v < /proc/version && [[ "$_v" == *[Mm]icrosoft* ]]; then
  _IS_WSL=1
else
  _IS_WSL=0
fi

# ------------------------------------------------------------------------------
# WSL
# ------------------------------------------------------------------------------

if (( _IS_WSL )); then
  export BROWSER="wsl-open"

  # Prevent Claude Code from repeatedly spawning powershell.exe
  # https://zenn.dev/momonga/articles/ee5b114e038938
  # https://github.com/anthropics/claude-code/issues/14352
  export CLAUDE_CODE_SKIP_WINDOWS_PROFILE=1
  # PowerShell Constrained Language Mode で Claude Code の /copy が初回失敗するため除外
  # https://github.com/anthropics/claude-code/issues/XXXXX
  path=(${path:#*/WindowsPowerShell/*})
  export USERPROFILE="/mnt/c/Users/$(whoami)"
  export WEZTERM_HOSTNAME="$(< /proc/sys/kernel/hostname)"

  # fzf: Ctrl+Y で選択行を Windows クリップボードへコピー
  # FZF_DEFAULT_OPTS は fzf 側でシェル風に分割されるため、空白・|・() を含む bind 値はシングルクォート必須
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }--bind='ctrl-y:execute-silent(echo -n {} | clip.exe)'"

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
function precmd_wsl() {
  if (( _IS_WSL )); then
    printf "\033]7;file://%s%s\033\\" "${HOSTNAME}" "${PWD}"
  fi
}

autoload -U add-zsh-hook
add-zsh-hook precmd precmd_wsl
