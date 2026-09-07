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

# ast-grep: Linux では util-linux の sg(switch-group) と衝突するため alias で上書き
# https://ast-grep.github.io/guide/quick-start.html#linux
alias sg='ast-grep'

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
  path=(${path:#*/WindowsPowerShell/*})
  export USERPROFILE="/mnt/c/Users/$(whoami)"
  export WEZTERM_HOSTNAME="$(< /proc/sys/kernel/hostname)"

  # fzf: Ctrl+Y で選択行を Windows クリップボードへコピー
  # WSLg が X クリップボードと Windows クリップボードを双方向同期するため xsel で届く。
  # win32yank.exe は UTF-8 は扱えるが Windows プロセスの起動に実測 462ms かかる (xsel は 9ms)
  # FZF_DEFAULT_OPTS は fzf 側でシェル風に分割されるため、空白・|・() を含む bind 値はシングルクォート必須
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }--bind='ctrl-y:execute-silent(echo -n {} | xsel -ib)'"

  # VPN 経由の通信のため eth0 の MTU を 1400 にする必要があるが、それは
  # /etc/wsl.conf の [boot] command (root で起動時に 1 回) で行う。
  # https://blog.adglobe.co.jp/entry/2024/07/31/100000
fi

# https://github.com/wezterm/wezterm/issues/5503
# https://github.com/wezterm/wezterm/issues/5503#issuecomment-2600490028
function precmd_wsl() {
  if (( _IS_WSL )); then
    # zsh は HOSTNAME を設定しない (HOST のみ) ため、上で求めた WEZTERM_HOSTNAME を使う
    printf "\033]7;file://%s%s\033\\" "${WEZTERM_HOSTNAME}" "${PWD}"
  fi
}

autoload -U add-zsh-hook
add-zsh-hook precmd precmd_wsl
