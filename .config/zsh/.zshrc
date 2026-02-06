# ------------------------------------------------------------------------------
# Zsh Profiling
# ------------------------------------------------------------------------------

# zmodload zsh/zprof && zprof

# ------------------------------------------------------------------------------
# Zim (https://github.com/zimfw/zimfw)
# ------------------------------------------------------------------------------

ZIM_HOME=${ZDOTDIR:-${HOME}}/.zim
ZIM_CONFIG_FILE=${ZDOTDIR:-${HOME}}/.zimrc
# Download zimfw plugin manager if missing.
if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
      https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  else
    mkdir -p ${ZIM_HOME} && wget -nv -O ${ZIM_HOME}/zimfw.zsh \
      https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  fi
fi

# zimfwの初期化（init.zshが古い場合は再生成）
if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]]; then
  source ${ZIM_HOME}/zimfw.zsh init -q
fi

# _evalcacheを利用可能にするため、最小限のモジュールを読み込み
source ${ZIM_HOME}/init.zsh

# Emacs キーバインドを使用（vi モードを無効化）
bindkey -e

# ------------------------------------------------------------------------------
# Zsh
# ------------------------------------------------------------------------------

# OS依存の設定
local os=$(uname | tr '[:upper:]' '[:lower:]')
[ -f $ZDOTDIR/"$os".zsh ] && . $ZDOTDIR/"$os".zsh

# 分離された設定ファイルを読み込む (ディレクトリがなければ作成)
[ -d "$ZDOTDIR/config.d" ] || mkdir -p "$ZDOTDIR/config.d"
for conf in "$ZDOTDIR/config.d/"*.zsh(N); do
  source "${conf}"
done

# カスタム関数を読み込む
[ -d "$ZDOTDIR/functions.d" ] || mkdir -p "$ZDOTDIR/functions.d"
for func in "$ZDOTDIR/functions.d/"*.zsh(N); do
  source "${func}"
done

# ------------------------------------------------------------------------------
# mise (https://github.com/jdx/mise)
# ------------------------------------------------------------------------------

if command -v mise &>/dev/null; then
  _evalcache mise activate zsh
fi

# History
# History file
export HISTFILE="$ZDOTDIR/.zsh_history"
# History size
export HISTSIZE=10000
# Save history
export SAVEHIST=10000
# Ignore duplicate commands
setopt hist_ignore_dups
# Ignore all duplicate commands
setopt hist_ignore_all_dups
# Reduce duplicate commands
setopt hist_reduce_blanks
# Share history
setopt share_history
# Disable beep
setopt no_beep

# Alias
. $ZDOTDIR/aliases.zsh

# Editor
export EDITOR="nvim"
# export EDITOR="hx"

# ------------------------------------------------------------------------------
# bat (https://github.com/sharkdp/bat)
# ------------------------------------------------------------------------------

export BAT_CONFIG_DIR="${XDG_CONFIG_HOME}/bat"

# ------------------------------------------------------------------------------
# Cargo (https://github.com/rust-lang/cargo)
# ------------------------------------------------------------------------------

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# ------------------------------------------------------------------------------
# Claude Code (https://docs.anthropic.com/ja/docs/claude-code/overview)
# ------------------------------------------------------------------------------

export CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"
export CLAUDE_CODE_TERMINAL=0

# ------------------------------------------------------------------------------
# Cursor (https://www.cursor.com)
# ------------------------------------------------------------------------------

# https://zenn.dev/rasuharu/articles/b2e5333b29fbcd
export TERM_PROGRAM="${TERM_PROGRAM:-unknown}"
export CURSOR_TERMINAL="${CURSOR_TERMINAL:-0}"

# Cursor環境でのみ追加設定を適用
if [[ "$TERM_PROGRAM" == "vscode" ]] || [[ -n "$CURSOR_TERMINAL" ]]; then
  # Shell integrationを無効化（競合回避）
  export VSCODE_SHELL_INTEGRATION=0
fi

# ------------------------------------------------------------------------------
# Delta (https://github.com/dandavison/delta)
# ------------------------------------------------------------------------------

zsh-defer -c '[ -e "$ZIM_HOME/modules/zsh-completions/src/_delta" ] || delta --generate-completion zsh >$ZIM_HOME/modules/zsh-completions/src/_delta'

# ------------------------------------------------------------------------------
# DuckDB (https://github.com/duckdb/duckdb)
# ------------------------------------------------------------------------------

[ -e "$HOME/.duckdbrc" ] || {
  ln -s "$XDG_CONFIG_HOME/duckdb/duckdbrc" "$HOME/.duckdbrc"
}

# ------------------------------------------------------------------------------
# fastfetch (https://github.com/fastfetch-cli/fastfetch)
# ------------------------------------------------------------------------------

[ -e "$HOME/.config/fastfetch/config.jsonc" ] || {
  mkdir -p "$HOME/.config/fastfetch"
  ln -s "$XDG_CONFIG_HOME/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
}

# Cursor環境の場合はスキップ
# if [[ "$TERM_PROGRAM" != "vscode" ]] && [[ "$CURSOR_TERMINAL" == "0" ]]; then
#   fastfetch
# fi

# ------------------------------------------------------------------------------
# fzf (https://github.com/junegunn/fzf)
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a \
--color=border:#6c7086,label:#cdd6f4"

# ------------------------------------------------------------------------------
# Lazygit (https://github.com/jesseduffield/lazygit)
# ------------------------------------------------------------------------------

export LG_CONFIG_FILE=$XDG_CONFIG_HOME/lazygit/config.yml,$XDG_CONFIG_HOME/lazygit/catppuccin-mocha-blue.yml

# ------------------------------------------------------------------------------
# ls
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/catppuccin/discussions/2220
# https://github.com/catppuccin/catppuccin/discussions/2220#discussioncomment-9476399
export LS_COLORS="$(vivid generate catppuccin-mocha)"

# ------------------------------------------------------------------------------
# psql (https://www.postgresql.org/docs/current/app-psql.html)
# ------------------------------------------------------------------------------

export PSQLRC=${XDG_CONFIG_HOME}/pg/.psqlrc

# ------------------------------------------------------------------------------
# ripgrep (https://github.com/BurntSushi/ripgrep)
# ------------------------------------------------------------------------------

export RIPGREP_CONFIG_PATH=$XDG_CONFIG_HOME/.ripgreprc

# ------------------------------------------------------------------------------
# Starship (https://github.com/starship/starship)
# ------------------------------------------------------------------------------

_evalcache starship init zsh

# ------------------------------------------------------------------------------
# WezTerm (https://github.com/wezterm/wezterm)
# ------------------------------------------------------------------------------

zsh-defer _evalcache wezterm shell-completion --shell zsh
. $ZDOTDIR/wezterm-integration.sh

# ------------------------------------------------------------------------------
# Yazi (https://github.com/sxyazi/yazi)
# ------------------------------------------------------------------------------

alias y='yazi'
# https://yazi-rs.github.io/docs/quick-start/#shell-wrapper
function yi() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# ------------------------------------------------------------------------------
# zoxide (https://github.com/ajeetdsouza/zoxide)
# ------------------------------------------------------------------------------

export _ZO_FZF_OPTS='
--no-sort --height 75% --reverse --margin=0,1 --exit-0 --select-1
--prompt="❯ "
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
--color=selected-bg:#45475a
--color=border:#6c7086,label:#cdd6f4
--preview "([[ -e '{2..}/README.md' ]] && bat --color=always --style=numbers --line-range=:50 '{2..}/README.md') || eza --color=always --group-directories-first --oneline {2..}"
'
zsh-defer _evalcache zoxide init zsh

# ------------------------------------------------------------------------------
# Zsh Profiling
# ------------------------------------------------------------------------------

# if (which zprof > /dev/null) ;then
#   zprof | bat --language=zsh --style="grid"
# fi
