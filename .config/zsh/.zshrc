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

# zimfw() 関数の定義（zimfw コマンド用）
if [[ -e ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]] zimfw() { source ${ZIM_HOME}/zimfw.zsh "${@}" }

# fpath 設定（autoload 用、コスト: ~0ms）
fpath=(
  ${ZIM_HOME}/modules/git/functions
  ${ZIM_HOME}/modules/utility/functions
  ${ZIM_HOME}/modules/zsh-completions/src
  ${fpath}
)
autoload -Uz -- git-alias-lookup git-branch-current git-branch-delete-interactive \
  git-branch-remote-tracking git-dir git-ignore-add git-root \
  git-stash-clear-interactive git-stash-recover git-submodule-move \
  git-submodule-remove mkcd mkpw

# 即座に読み込み（プロンプト表示に必須）
source ${ZIM_HOME}/modules/zsh-defer/zsh-defer.plugin.zsh
source ${ZIM_HOME}/modules/evalcache/evalcache.plugin.zsh
source ${ZIM_HOME}/modules/environment/init.zsh
source ${ZIM_HOME}/modules/input/init.zsh

# zimfwの初期化（init.zshが古い場合は遅延で再生成）
if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]]; then
  zsh-defer -a +1 +2 source ${ZIM_HOME}/zimfw.zsh init -q
fi

# 遅延読み込み（初回プロンプト後に読み込み）
# -a +1 +2: 全フラグ無効 → stdout/stderr リダイレクトのみ有効
# 個別タスクにすることで、タスク間で KEYS_QUEUED_COUNT チェックが入り
# キー入力があれば即座に表示される（入力応答性優先）
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/utility/init.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/git/init.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/termtitle/init.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/git-open/git-open.plugin.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/completion/init.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/zsh-history-substring-search/zsh-history-substring-search.zsh
zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/zsh-autosuggestions/zsh-autosuggestions.zsh

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

# _evalcache はキャッシュ済みでも md5sum 計算で fork するため、直接 source する
zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-mise-*.sh(Nom[1])); [[ -n $f ]] && source $f || { command -v mise &>/dev/null && _evalcache mise activate zsh; }; }'

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

zsh-defer -a +1 +2 -c '[ -e "$ZIM_HOME/modules/zsh-completions/src/_delta" ] || delta --generate-completion zsh >$ZIM_HOME/modules/zsh-completions/src/_delta'

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

LG_CONFIG_FILE=$XDG_CONFIG_HOME/lazygit/config.yml,$XDG_CONFIG_HOME/lazygit/catppuccin-mocha-blue.yml
if (( _IS_WSL )); then
  LG_CONFIG_FILE="$LG_CONFIG_FILE,$XDG_CONFIG_HOME/lazygit/config.wsl.yml"
fi
export LG_CONFIG_FILE

# ------------------------------------------------------------------------------
# ls
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/catppuccin/discussions/2220
# https://github.com/catppuccin/catppuccin/discussions/2220#discussioncomment-9476399
if [[ ! -f "$ZSH_EVALCACHE_DIR/ls_colors_cache" ]]; then
  vivid generate catppuccin-mocha > "$ZSH_EVALCACHE_DIR/ls_colors_cache"
fi
export LS_COLORS="$(< $ZSH_EVALCACHE_DIR/ls_colors_cache)"

# ------------------------------------------------------------------------------
# psql (https://www.postgresql.org/docs/current/app-psql.html)
# ------------------------------------------------------------------------------

export PSQLRC=${XDG_CONFIG_HOME}/pg/.psqlrc

# ------------------------------------------------------------------------------
# ripgrep (https://github.com/BurntSushi/ripgrep)
# ------------------------------------------------------------------------------

export RIPGREP_CONFIG_PATH=$XDG_CONFIG_HOME/.ripgreprc

# ------------------------------------------------------------------------------
# taplo (https://github.com/tamasfe/taplo)
# ------------------------------------------------------------------------------

export TAPLO_CONFIG=$XDG_CONFIG_HOME/taplo/taplo.toml

# ------------------------------------------------------------------------------
# Starship (https://github.com/starship/starship)
# ------------------------------------------------------------------------------

# _evalcache を経由すると command -v が $commands ハッシュテーブル構築をトリガーし
# WSL の /mnt/c/ PATH スキャンで ~200ms かかるため、キャッシュファイルを直接 source する
# キャッシュ再生成: rm "$ZSH_EVALCACHE_DIR/starship-init.zsh"
() {
  local cache="$ZSH_EVALCACHE_DIR/starship-init.zsh"
  if [[ ! -f "$cache" ]]; then
    starship init zsh --print-full-init > "$cache"
    zcompile "$cache" 2>/dev/null
  fi
  source "$cache"
}

# ------------------------------------------------------------------------------
# WezTerm (https://github.com/wezterm/wezterm)
# ------------------------------------------------------------------------------

zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-wezterm-*.sh(Nom[1])); [[ -n $f ]] && source $f || _evalcache wezterm shell-completion --shell zsh; }'
[[ -n "${WEZTERM_PANE}" ]] && . $ZDOTDIR/wezterm-integration.sh

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
zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-zoxide-*.sh(Nom[1])); [[ -n $f ]] && source $f || _evalcache zoxide init zsh; }'

# 全遅延タスク完了後に1回だけpromptを再描画
zsh-defer -c 'zle reset-prompt'

# ------------------------------------------------------------------------------
# Zsh Profiling
# ------------------------------------------------------------------------------

# if (which zprof > /dev/null) ;then
#   zprof | bat --language=zsh --style="grid"
# fi
