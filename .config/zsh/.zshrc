# ------------------------------------------------------------------------------
# Zsh Profiling
# ------------------------------------------------------------------------------

# zmodload zsh/zprof && zprof

# ------------------------------------------------------------------------------
# Plugins
# ------------------------------------------------------------------------------

# 各プラグインは Home Manager が配置する (programs/zsh.nix)
ZSH_PLUGIN_DIR=$ZDOTDIR/plugins

# fpath 設定（autoload 用、コスト: ~0ms）
fpath=(
  ${ZSH_PLUGIN_DIR}/git/functions
  ${ZSH_PLUGIN_DIR}/utility/functions
  ${ZSH_PLUGIN_DIR}/zsh-completions
  ${fpath}
)
autoload -Uz -- git-alias-lookup git-branch-current git-branch-delete-interactive \
  git-branch-remote-tracking git-dir git-ignore-add git-root \
  git-stash-clear-interactive git-stash-recover git-submodule-move \
  git-submodule-remove mkcd mkpw

# 即座に読み込み（プロンプト表示に必須）
source ${ZSH_PLUGIN_DIR}/zsh-defer/zsh-defer.plugin.zsh
source ${ZSH_PLUGIN_DIR}/evalcache/evalcache.plugin.zsh
# evalcache はキャッシュミス時にしかディレクトリを作らず、下の vivid は
# ディレクトリがある前提で書き込む
[[ -d "${ZSH_EVALCACHE_DIR}" ]] || mkdir -p "${ZSH_EVALCACHE_DIR}"
# 自前生成の補完 (delta など)。プラグインディレクトリは Nix store を指し書き込めない
fpath=(${ZSH_EVALCACHE_DIR}/completions ${fpath})
source ${ZSH_PLUGIN_DIR}/environment/init.zsh
# EDITOR=nvim だと main が viins になり、input の bindkey が emacs に届かないため先に切り替える
bindkey -e
source ${ZSH_PLUGIN_DIR}/input/init.zsh

# edit-command-line は input モジュールが autoload と zle -N 済み
bindkey '^G' edit-command-line
bindkey '^[q' push-line-or-edit
autoload -Uz copy-earlier-word && zle -N copy-earlier-word
bindkey '^[,' copy-earlier-word

# 遅延読み込み（初回プロンプト後に読み込み）
# -a +1 +2: 全フラグ無効 → stdout/stderr リダイレクトのみ有効
# 個別タスクにすることで、タスク間で KEYS_QUEUED_COUNT チェックが入り
# キー入力があれば即座に表示される（入力応答性優先）
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/utility/init.zsh
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/git/init.zsh
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/termtitle/init.zsh
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/completion/init.zsh
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/zsh-history-substring-search/zsh-history-substring-search.zsh
zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh
zsh-defer -a +1 +2 -c 'bindkey "^[g" autosuggest-clear'

# ↑↓ を substring 検索に割り当てる (プラグイン側は bindkey を一切設定しないため、
# 未指定だと zim input モジュールの up/down-line-or-history のままロードだけされる)
# ^[[A/^[[B は通常モード、^[OA/^[OB は application cursor モード (WezTerm)
zsh-defer -a +1 +2 -c 'bindkey "^[[A" history-substring-search-up; bindkey "^[OA" history-substring-search-up'
zsh-defer -a +1 +2 -c 'bindkey "^[[B" history-substring-search-down; bindkey "^[OB" history-substring-search-down'

# ------------------------------------------------------------------------------
# zeno.zsh (https://github.com/yuki-yano/zeno.zsh)
# ------------------------------------------------------------------------------

export ZENO_HOME="${XDG_CONFIG_HOME}/zeno"
export ZENO_GIT_CAT="bat --color=always"
export ZENO_GIT_TREE="eza --tree"
# 依存は Nix パッケージに同梱されているため、起動時の取得を止める。
export ZENO_DISABLE_EXECUTE_CACHE_COMMAND=1

# fzf key bindings (Ctrl+T, Alt+C) — zeno より先に読み込み、Tab/Ctrl+R は zeno が上書き
zsh-defer -a +1 +2 -c 'source <(fzf --zsh)'

zsh-defer -a +1 +2 source ${ZSH_PLUGIN_DIR}/zeno.zsh/zeno.zsh
zsh-defer -a +1 +2 -c '(( $+widgets[zeno-auto-snippet] )) && bindkey " " zeno-auto-snippet'
zsh-defer -a +1 +2 -c '(( $+widgets[zeno-auto-snippet-and-accept-line] )) && bindkey "^m" zeno-auto-snippet-and-accept-line'
zsh-defer -a +1 +2 -c '(( $+widgets[zeno-completion] )) && bindkey "^i" zeno-completion'
zsh-defer -a +1 +2 -c '(( $+widgets[zeno-smart-history-selection] )) && bindkey "^r" zeno-smart-history-selection'
zsh-defer -a +1 +2 -c '(( $+widgets[zeno-insert-space] )) && bindkey "^x " zeno-insert-space'
zsh-defer -a +1 +2 -c 'bindkey "^x^m" accept-line'

# 単語区切りから / . = を外し、Ctrl+W / Alt+B などをパス構成要素単位で効かせる
# (デフォルトの WORDCHARS は / を含むため Ctrl+W がパス全体を消してしまう)
WORDCHARS=${WORDCHARS//[\/.=]}

# Ctrl+S / Ctrl+Q によるフロー制御を無効化 (誤爆でターミナルが固まるのを防ぐ)
unsetopt flow_control

# ------------------------------------------------------------------------------
# Zsh
# ------------------------------------------------------------------------------

# OS依存の設定（外部コマンドを起動せず Zsh 組み込み値から判定）
local os
case $OSTYPE in
  darwin*) os=darwin ;;
  linux*) os=linux ;;
esac
[[ -n $os && -f $ZDOTDIR/"$os".zsh ]] && . $ZDOTDIR/"$os".zsh

# 分離された設定ファイルを読み込む (ディレクトリは zsh.nix の activation が作る)
for conf in "$ZDOTDIR/config.d/"*.zsh(N); do
  source "${conf}"
done

for func in "$ZDOTDIR/functions.d/"*.zsh(N); do
  source "${func}"
done

# ------------------------------------------------------------------------------
# mise (https://github.com/jdx/mise)
# ------------------------------------------------------------------------------

# _evalcache はキャッシュ済みでも md5sum 計算で fork するため、直接 source する
zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-mise-*.sh(Nom[1])); [[ -n $f ]] && source $f || { command -v mise &>/dev/null && _evalcache mise activate zsh; }; }'

export HISTFILE="$ZDOTDIR/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt share_history
# 履歴に実行時刻と所要時間を記録する (fc -li で参照可能)
setopt extended_history
setopt hist_save_no_dups
# history / fc コマンド自体は履歴に残さない
setopt hist_no_store
# 履歴ファイルの読み書きを fcntl でロックする
# share_history + herdr の多ペイン同時書き込みでの破損を防ぐ
setopt hist_fcntl_lock
setopt no_beep

. $ZDOTDIR/functions.zsh

# GEM_HOME (hm-session-vars.sh の PATH 設定が WezTerm WSL ドメインで反映されない問題の回避)
[[ -d "$XDG_DATA_HOME/gem/bin" ]] && [[ ":$PATH:" != *":$XDG_DATA_HOME/gem/bin:"* ]] && export PATH="$XDG_DATA_HOME/gem/bin:$PATH"

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

[[ -d "$XDG_DATA_HOME/cargo/bin" ]] && [[ ":$PATH:" != *":$XDG_DATA_HOME/cargo/bin:"* ]] && export PATH="$XDG_DATA_HOME/cargo/bin:$PATH"

# ------------------------------------------------------------------------------
# Claude Code (https://docs.anthropic.com/ja/docs/claude-code/overview)
# ------------------------------------------------------------------------------

# Claude Code は TERM_PROGRAM の許可リストでしか OSC 8 リンクを出さず、herdr は未掲載
# https://github.com/herdrdev/herdr/issues/4748
[[ "$TERM_PROGRAM" == herdr ]] && export FORCE_HYPERLINK=1

# ------------------------------------------------------------------------------
# Cursor (https://www.cursor.com)
# ------------------------------------------------------------------------------

# https://zenn.dev/rasuharu/articles/b2e5333b29fbcd
export TERM_PROGRAM="${TERM_PROGRAM:-unknown}"
export CURSOR_TERMINAL="${CURSOR_TERMINAL:-0}"

# (CURSOR_TERMINAL は上で "0" に初期化するため、空判定ではなく値で比較する)
if [[ "$TERM_PROGRAM" == "vscode" ]] || [[ "$CURSOR_TERMINAL" == 1 ]]; then
  # Shell integrationを無効化（競合回避）
  export VSCODE_SHELL_INTEGRATION=0
fi

# ------------------------------------------------------------------------------
# Delta (https://github.com/dandavison/delta)
# ------------------------------------------------------------------------------

zsh-defer -a +1 +2 -c '[ -e "$ZSH_EVALCACHE_DIR/completions/_delta" ] || { mkdir -p "$ZSH_EVALCACHE_DIR/completions" && delta --generate-completion zsh >"$ZSH_EVALCACHE_DIR/completions/_delta"; }'

# ------------------------------------------------------------------------------
# ls
# ------------------------------------------------------------------------------

# https://github.com/catppuccin/catppuccin/discussions/2220
# https://github.com/catppuccin/catppuccin/discussions/2220#discussioncomment-9476399
if [[ ! -s "$ZSH_EVALCACHE_DIR/ls_colors_cache" ]]; then
  vivid generate ${CATPPUCCIN_VIVID_THEME:-catppuccin-mocha} >| "$ZSH_EVALCACHE_DIR/ls_colors_cache"
fi
export LS_COLORS="$(< $ZSH_EVALCACHE_DIR/ls_colors_cache)"

# ------------------------------------------------------------------------------
# Starship (https://github.com/starship/starship)
# ------------------------------------------------------------------------------

source "$ZDOTDIR/starship-init.zsh"

# ------------------------------------------------------------------------------
# tdf (https://github.com/itsjunetime/tdf)
# ------------------------------------------------------------------------------

# tdf が使う ratatui-image は TERM_PROGRAM に WezTerm/iTerm 等が含まれると
# capability クエリの結果より env からの推測を優先し iTerm2 プロトコルを選ぶ。
# tdf は Kitty 専用実装のため、その場合は画像シーケンスを一切出さずページが空になる
alias tdf='TERM_PROGRAM= tdf'

# ------------------------------------------------------------------------------
# WezTerm (https://github.com/wezterm/wezterm)
# ------------------------------------------------------------------------------

zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-wezterm-*.sh(Nom[1])); [[ -n $f ]] && source $f || _evalcache wezterm shell-completion --shell zsh; }'
[[ -n "${WEZTERM_PANE}" ]] && . $ZDOTDIR/wezterm-integration.sh

# ------------------------------------------------------------------------------
# zoxide (https://github.com/ajeetdsouza/zoxide)
# ------------------------------------------------------------------------------

export _ZO_FZF_OPTS="--no-sort --height 75% --reverse --margin=0,1 --exit-0 --select-1 --prompt=\"❯ \" --preview \"([[ -e {2..}/README.md ]] && bat --color=always --style=numbers --line-range=:50 {2..}/README.md) || eza --color=always --group-directories-first --oneline {2..}\""
zsh-defer -a +1 +2 -c '() { local f=($ZSH_EVALCACHE_DIR/init-zoxide-*.sh(Nom[1])); [[ -n $f ]] && source $f || _evalcache zoxide init zsh; }'

# 全遅延タスク完了後に1回だけpromptを再描画
zsh-defer -c 'zle reset-prompt'

# ------------------------------------------------------------------------------
# Zsh Profiling
# ------------------------------------------------------------------------------

# if (which zprof > /dev/null) ;then
#   zprof | bat --language=zsh --style="grid"
# fi
