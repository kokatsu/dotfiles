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
if [[ -e ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]] zimfw() {
  source ${ZIM_HOME}/zimfw.zsh "${@}"
  # zeno-completion の local options が zsh/parameter の $options をシャドウし
  # _zsh_highlight で "bad set of key/value pairs" エラーになる問題を修正
  local _f=${ZIM_HOME}/modules/zeno.zsh/shells/zsh/widgets/zeno-completion
  if [[ -f $_f ]] && grep -q 'local.*expect_key options ' $_f; then
    sed -i '' 's/expect_key options /expect_key fzf_options /' $_f
    sed -i '' 's/^options=/fzf_options=/' $_f
    sed -i '' 's/${options}/${fzf_options}/g' $_f
    sed -i '' 's/${(z)options}/${(z)fzf_options}/g' $_f
  fi
}

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

# ------------------------------------------------------------------------------
# zeno.zsh (https://github.com/yuki-yano/zeno.zsh)
# ------------------------------------------------------------------------------

export ZENO_HOME="${XDG_CONFIG_HOME}/zeno"
export ZENO_GIT_CAT="bat --color=always"
export ZENO_GIT_TREE="eza --tree"

# zeno-completion の local options が zsh/parameter の $options をシャドウし
# _zsh_highlight で "bad set of key/value pairs" エラーになる問題を修正
() {
  local _f=${ZIM_HOME}/modules/zeno.zsh/shells/zsh/widgets/zeno-completion
  if [[ -f $_f ]] && grep -q 'local.*expect_key options ' $_f; then
    sed -i '' 's/expect_key options /expect_key fzf_options /' $_f
    sed -i '' 's/^options=/fzf_options=/' $_f
    sed -i '' 's/${options}/${fzf_options}/g' $_f
    sed -i '' 's/${(z)options}/${(z)fzf_options}/g' $_f
  fi
}

# fzf key bindings (Ctrl+T, Alt+C) — zeno より先に読み込み、Tab/Ctrl+R は zeno が上書き
zsh-defer -a +1 +2 -c 'source <(fzf --zsh)'
# Ctrl+T は WezTerm の新規タブと衝突するため Alt+T にリマップ
zsh-defer -a +1 +2 -c 'bindkey -r "^T"; bindkey "^[t" fzf-file-widget'

zsh-defer -a +1 +2 source ${ZIM_HOME}/modules/zeno.zsh/zeno.zsh
zsh-defer -a +1 +2 -c 'bindkey " " zeno-auto-snippet'
zsh-defer -a +1 +2 -c 'bindkey "^m" zeno-auto-snippet-and-accept-line'
zsh-defer -a +1 +2 -c 'bindkey "^i" zeno-completion'
zsh-defer -a +1 +2 -c 'bindkey "^r" zeno-smart-history-selection'
zsh-defer -a +1 +2 -c 'bindkey "^x " zeno-insert-space'
zsh-defer -a +1 +2 -c 'bindkey "^x^m" accept-line'

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

# Functions
. $ZDOTDIR/functions.zsh

# GEM_HOME (hm-session-vars.sh の PATH 設定が WezTerm WSL ドメインで反映されない問題の回避)
[[ -d "$HOME/.gem/bin" ]] && [[ ":$PATH:" != *":$HOME/.gem/bin:"* ]] && export PATH="$HOME/.gem/bin:$PATH"

# EDITOR, BAT_CONFIG_DIR は home.sessionVariables で管理

# ------------------------------------------------------------------------------
# Carapace (https://github.com/carapace-sh/carapace-bin)
# ------------------------------------------------------------------------------

# マルチシェル補完。Zim の completion モジュール (compinit) より後に初期化するため
# zsh-defer キュー末尾に追加。CARAPACE_BRIDGES は補完実行時に参照されるので export
export CARAPACE_BRIDGES="zsh,bash"
zsh-defer -a +1 +2 -c '_evalcache carapace _carapace zsh'

# ------------------------------------------------------------------------------
# Cargo (https://github.com/rust-lang/cargo)
# ------------------------------------------------------------------------------

[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# ------------------------------------------------------------------------------
# Claude Code (https://docs.anthropic.com/ja/docs/claude-code/overview)
# ------------------------------------------------------------------------------

# CLAUDE_CONFIG_DIR は home.sessionVariables で管理
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

# fastfetch は home.file で管理

# ------------------------------------------------------------------------------
# fzf (https://github.com/junegunn/fzf)
# ------------------------------------------------------------------------------

# fzf colors は catppuccin/nix (programs.fzf.colors) で管理
# FZF_DEFAULT_OPTS は home.sessionVariables 経由で設定される
# fzf key bindings は zeno.zsh セクションで読み込み（Tab の優先順位制御のため）

# ------------------------------------------------------------------------------
# Lazygit (https://github.com/jesseduffield/lazygit)
# ------------------------------------------------------------------------------

# lazygit の設定とテーマは catppuccin/nix + programs.lazygit で管理
# LG_CONFIG_FILE は home.sessionVariables 経由で設定される
if (( _IS_WSL )); then
  LG_CONFIG_FILE="${LG_CONFIG_FILE:+$LG_CONFIG_FILE,}$XDG_CONFIG_HOME/lazygit/config.wsl.yml"
fi
export LG_CONFIG_FILE

# ------------------------------------------------------------------------------
# ls
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/catppuccin/discussions/2220
# https://github.com/catppuccin/catppuccin/discussions/2220#discussioncomment-9476399
if [[ ! -f "$ZSH_EVALCACHE_DIR/ls_colors_cache" ]]; then
  vivid generate ${CATPPUCCIN_VIVID_THEME:-catppuccin-mocha} > "$ZSH_EVALCACHE_DIR/ls_colors_cache"
fi
export LS_COLORS="$(< $ZSH_EVALCACHE_DIR/ls_colors_cache)"

# PSQLRC, RIPGREP_CONFIG_PATH, TAPLO_CONFIG は home.sessionVariables で管理

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
# zoxide (https://github.com/ajeetdsouza/zoxide)
# ------------------------------------------------------------------------------

# Catppuccin パレット由来の色は Nix 生成ファイル側で管理 ($ZDOTDIR/catppuccin-colors.zsh)
[[ -f "$ZDOTDIR/catppuccin-colors.zsh" ]] && source "$ZDOTDIR/catppuccin-colors.zsh"

export _ZO_FZF_OPTS="--no-sort --height 75% --reverse --margin=0,1 --exit-0 --select-1 --prompt=\"❯ \" ${FZF_CATPPUCCIN_COLORS} --preview \"([[ -e '{2..}/README.md' ]] && bat --color=always --style=numbers --line-range=:50 '{2..}/README.md') || eza --color=always --group-directories-first --oneline {2..}\""
zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-zoxide-*.sh(Nom[1])); [[ -n $f ]] && source $f || _evalcache zoxide init zsh; }'

# 全遅延タスク完了後に1回だけpromptを再描画
zsh-defer -c 'zle reset-prompt'

# ------------------------------------------------------------------------------
# Zsh Profiling
# ------------------------------------------------------------------------------

# if (which zprof > /dev/null) ;then
#   zprof | bat --language=zsh --style="grid"
# fi
