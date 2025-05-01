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
# Install missing modules and update ${ZIM_HOME}/init.zsh if missing or outdated.
if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE} ]]; then
  source "$(brew --prefix zimfw)/share/zimfw.zsh" init
fi
# Initialize modules.
source ${ZIM_HOME}/init.zsh

# ------------------------------------------------------------------------------
# Zsh
# ------------------------------------------------------------------------------

# OS依存の設定
local os=$(uname | tr '[:upper:]' '[:lower:]')
[ -f $ZDOTDIR/"$os".zsh ] && . $ZDOTDIR/"$os".zsh

# 分離された設定ファイルを読み込む
if [ -d "$ZDOTDIR/config.d" ]; then
  for conf in "$ZDOTDIR/config.d/"*.zsh; do
    [ -e "$conf" ] || break
    source "${conf}"
  done
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

# Alias
. $ZDOTDIR/aliases.zsh

# ------------------------------------------------------------------------------
# Bat (https://github.com/sharkdp/bat)
# ------------------------------------------------------------------------------

export BAT_CONFIG_DIR="${XDG_CONFIG_HOME}/bat"

# ------------------------------------------------------------------------------
# Delta (https://github.com/dandavison/delta)
# ------------------------------------------------------------------------------

[ -e "$ZIM_HOME/modules/zsh-completions/src/_delta" ] || delta --generate-completion zsh >$ZIM_HOME/modules/zsh-completions/src/_delta

# ------------------------------------------------------------------------------
# fastfetch (https://github.com/fastfetch-cli/fastfetch)
# ------------------------------------------------------------------------------

[ -e "$HOME/.config/fastfetch/config.jsonc" ] || {
  mkdir -p "$HOME/.config/fastfetch"
  ln -s "$XDG_CONFIG_HOME/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
}

fastfetch

# ------------------------------------------------------------------------------
# fzf (https://github.com/junegunn/fzf)
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a \
--color=border:#313244,label:#cdd6f4"

# ------------------------------------------------------------------------------
# Lazygit (https://github.com/jesseduffield/lazygit)
# ------------------------------------------------------------------------------

lg() {
  export LAZYGIT_NEW_DIR_FILE=~/.lazygit/newdir

  lazygit "$@"

  if [ -f $LAZYGIT_NEW_DIR_FILE ]; then
    cd "$(cat $LAZYGIT_NEW_DIR_FILE)"
    rm -f $LAZYGIT_NEW_DIR_FILE >/dev/null
  fi
}

# ------------------------------------------------------------------------------
# ls
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/catppuccin/discussions/2220
# https://github.com/catppuccin/catppuccin/discussions/2220#discussioncomment-9476399
export LS_COLORS="$(vivid generate catppuccin-mocha)"

# ------------------------------------------------------------------------------
# psql (https://www.postgresql.org/docs/current/app-psql.html)
# ------------------------------------------------------------------------------

export PSQLRC="${XDG_CONFIG_HOME}/pg/.psqlrc"

# ------------------------------------------------------------------------------
# ripgrep (https://github.com/BurntSushi/ripgrep)
# ------------------------------------------------------------------------------

export RIPGREP_CONFIG_PATH=$XDG_CONFIG_HOME/.ripgreprc

# ------------------------------------------------------------------------------
# Starship (https://github.com/starship/starship)
# ------------------------------------------------------------------------------

eval "$(starship init zsh)"

# ------------------------------------------------------------------------------
# Yazi (https://github.com/sxyazi/yazi)
# ------------------------------------------------------------------------------

# https://yazi-rs.github.io/docs/quick-start/#shell-wrapper
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
