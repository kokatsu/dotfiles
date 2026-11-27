# shellcheck shell=bash
# nono-agent: Claude Code / Codex / Pi を nono の中で起動する。
#
# Usage:
#   nono-agent [nono run のオプション...] <claude|codex|pi> [args...]
#
# Landlock は pathname Unix socket への connect を止めず、WSL2 では nono の
# af_unix_mediation も使えない。systemd・docker・herdr・WSL interop の socket から
# サンドボックスの外でプロセスを起動できてしまうため、外側の bwrap で隠す。

usage() {
  echo "Usage: nono-agent [nono run options...] <claude|codex|pi> [args...]" >&2
  exit 2
}

nono_args=()
while (($# > 0)) && [[ $1 != claude && $1 != codex && $1 != pi ]]; do
  nono_args+=("$1")
  shift
done
(($# > 0)) || usage
agent=$1
shift

cwd=$(pwd -P)
home=$(realpath -- "$HOME")

for file in "$home"/.config/git/config.*; do
  [[ ! -f $file ]] || nono_args+=(--read-file "$file")
done
case $home/ in
"${cwd%/}"/*)
  echo "nono-agent: $cwd はホームディレクトリ全体を書き込み可能にするため起動しません" >&2
  exit 1
  ;;
esac
case $cwd/ in
/tmp/* | /private/* | /run/* | /mnt/* | "$home"/.config/* | "$home"/.local/* | "$home"/.cache/*)
  echo "nono-agent: $cwd からは起動できません" >&2
  exit 1
  ;;
esac

# .git が無いと中で作った .git を外の git が読む。worktree の .git はファイルで、実体が外にある
if [[ ! -d .git || -L .git ]]; then
  echo "nono-agent: git リポジトリのルートで起動してください (worktree は不可)" >&2
  exit 1
fi

if [[ -e .git/commondir && $(<.git/commondir) != ./ ]]; then
  echo "nono-agent: .git/commondir があるため保護できません" >&2
  exit 1
fi
hooks=$(realpath -m -- "$(git rev-parse --git-path hooks)")
# ルート自身を読み取り専用にすると作業できない
if [[ $hooks == "$cwd" ]]; then
  echo "nono-agent: core.hooksPath ($hooks) を保護できません" >&2
  exit 1
fi
# macOS の Seatbelt 規則は固定で、リポジトリごとの core.hooksPath を守れない
if [[ $(uname) == Darwin && $hooks == "$cwd"/* && $hooks != "$cwd/.git/hooks" ]]; then
  echo "nono-agent: core.hooksPath ($hooks) を保護できません" >&2
  exit 1
fi

data=$home/.local/share/nono-agent
mkdir -p "$data/claude/tmp" "$data/codex/tmp" "$data/pi/tmp"

case $agent in
claude)
  command=("$NONO_AGENT_CLAUDE" "$@")
  ;;
codex)
  command=("$NONO_AGENT_CODEX" -c 'sandbox_mode="danger-full-access"' -c 'approval_policy="on-request"')
  case ${1:-} in
  a | apply | completion | doctor | e | exec | features | help | login | logout | mcp | plugin | review) ;;
  *) command+=(--no-daemon) ;;
  esac
  command+=("$@")
  ;;
pi)
  command=("$NONO_AGENT_PI" "$@")
  ;;
esac

env_args=(
  CLAUDE_CONFIG_DIR="$data/claude"
  CLAUDE_CODE_TMPDIR="$data/claude/tmp"
  CODEX_HOME="$data/codex"
  PI_CODING_AGENT_DIR="$data/pi"
  TMPDIR="$data/$agent/tmp"
  TMPPREFIX="$data/$agent/tmp/zsh"
  NONO_AGENT_DATA="$data"
)
if [[ $agent == pi ]]; then
  env_args+=(
    FFF_FRECENCY_DB="$data/pi/fff/frecency"
    FFF_HISTORY_DB="$data/pi/fff/history"
  )
fi
for name in "${!HERDR_@}" "${!CLAUDE_CODE_MESSAGING_@}" "${!CLAUDE_CODE_CHILD_@}" "${!CLAUDE_CODE_SESSION_@}" \
  CLAUDECODE WSL_INTEROP WSLENV DISPLAY WAYLAND_DISPLAY PULSE_SERVER DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK DOCKER_HOST; do
  env_args=(-u "$name" "${env_args[@]}")
done
# nono は本体を別の pty で動かすため、Herdr はペインの foreground プロセスから判定できない。
# HERDR_AGENT は外側のプロセスにだけ持たせる
nono_command=(
  env "${env_args[@]}" HERDR_AGENT="$agent"
  nono run --silent --allow-cwd --profile "nono-agent-$agent" "${nono_args[@]}" --
  env -u HERDR_AGENT "${command[@]}"
)
export HERDR_AGENT=$agent

# 外の git や lefthook が後で読むもののうち、まだ存在せず読み取り専用にできないもの
list_lefthook() {
  find . .config -maxdepth 1 -regextype posix-extended \
    -regex '.*/\.?lefthook(-local)?\.(ya?ml|toml|jsonc?)' 2>/dev/null | sed 's|^\./||' | sort -u || true
}
list_risky() {
  list_lefthook
  find . -path ./.git -prune -o -mindepth 2 -name .git -print 2>/dev/null | sed 's|^\./||' | sort || true
}

locked=''
# shellcheck disable=SC2329 # trap から呼ぶ
cleanup() {
  if [[ -n $locked ]]; then
    local added
    added=$(comm -13 <(sort -u <<<"$risky_before") <(list_risky | sort -u))
    if [[ -n $added ]]; then
      printf 'nono-agent: セッション中に作られました。外で git や lefthook を使う前に確認してください:\n%s\n' "$added" >&2
    fi
    # マスクは外側で実体を消すと外れるため、最後のセッションだけが消す
    flock -x 10
    if flock -xn 9; then
      rm -f .git/commondir
      if [[ -f $created ]]; then
        while IFS= read -r path; do
          case $path in
          .claude | .codex | .pi) rmdir -- "$path" 2>/dev/null || true ;;
          esac
        done <"$created"
        rm -f -- "$created"
      fi
    fi
    flock -u 10
  fi
  if [[ -n ${HERDR_PANE_ID:-} ]]; then
    herdr pane report-metadata "$HERDR_PANE_ID" --source nono \
      --clear-display-agent >/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -n ${HERDR_PANE_ID:-} ]]; then
  herdr pane report-metadata "$HERDR_PANE_ID" --source nono \
    --display-agent $'\uf510'"  $agent" >/dev/null || true
fi

if [[ $(uname) == Darwin ]]; then
  status=0
  "${nono_command[@]}" || status=$?
  exit "$status"
fi

mounts=(
  --dev-bind / /
  --tmpfs /run
  --perms 0700 --dir "/run/user/$UID"
  --tmpfs /tmp
  --tmpfs /mnt
)
# bwrap は symlink 先のマウントポイントを作れない
if [[ -e /etc/resolv.conf ]]; then
  resolv=$(realpath -- /etc/resolv.conf)
  case $resolv in
  /run/* | /mnt/*) mounts+=(--ro-bind "$resolv" "$resolv") ;;
  esac
fi
if [[ -d $home/.config/herdr ]]; then
  mounts+=(--tmpfs "$home/.config/herdr")
  [[ ! -d $home/.config/herdr/hooks ]] ||
    mounts+=(--ro-bind "$home/.config/herdr/hooks" "$home/.config/herdr/hooks")
fi

# 後で隔離の外の git や Claude Code / Codex / Pi が実行するものを書き換えさせない。
# commondir があると git は config と hooks を別の場所から読むため、無害な値で先に作って固定する。
# "." だと libgit2 (Nix) がリポジトリを認識できない。
# 親を rename して差し替えられないよう、途中のディレクトリもマウントポイントにする
workspace_id=$(printf '%s' "$cwd" | sha256sum)
workspace_state="$data/workspaces/${workspace_id%% *}"
mkdir -p "$workspace_state"
created="$workspace_state/created"
# config の共有ロックでセッションを数え、別のロックで作成記録と後始末を直列化する。
exec 10>"$workspace_state/lock"
flock -x 10
exec 9<.git/config
flock -s 9
risky_before=$(list_risky)
locked=1
for path in .claude .codex .pi; do
  if [[ ! -e $path && ! -L $path ]]; then
    mkdir -- "$path"
    printf '%s\n' "$path" >>"$created"
  fi
done
mkdir -p .git/hooks .git/modules
[[ $hooks != "$cwd"/* ]] || mkdir -p "$hooks"
[[ -e .git/commondir ]] || echo ./ >.git/commondir
if [[ $(git config --bool extensions.worktreeConfig) == true ]]; then
  touch .git/config.worktree
fi
flock -u 10
protected=(.git/hooks .git/config .git/config.worktree .git/commondir .git/modules .claude .codex .pi)
[[ $hooks != "$cwd"/* ]] || protected+=("${hooks#"$cwd"/}")
mapfile -t lefthook < <(list_lefthook)
protected+=("${lefthook[@]}")
if [[ $cwd == "$(realpath -- "$NONO_AGENT_DOTFILES")" ]]; then
  read -ra live <<<"$NONO_AGENT_LIVE_PATHS"
  protected+=("${live[@]}")
fi
declare -A bound=()
read_only=()
watched=()
for path in "${protected[@]}"; do
  [[ -e $path || -L $path ]] || continue
  partial=''
  IFS=/ read -ra parts <<<"$path"
  for part in "${parts[@]}"; do
    partial=${partial:+$partial/}$part
    if [[ -L $partial ]]; then
      echo "nono-agent: $partial が symlink のため保護できません" >&2
      exit 1
    fi
    if [[ $partial != "$path" && -z ${bound[$partial]:-} ]]; then
      bound[$partial]=1
      mounts+=(--bind "$cwd/$partial" "$cwd/$partial")
    fi
  done
  read_only+=(--ro-bind "$cwd/$path" "$cwd/$path")
  watched+=("$cwd/$path")
done
mounts+=("${read_only[@]}")

unit=nono-agent-$$.scope
exec 8> >(
  if IFS= read -r lost; then
    systemctl --user kill --signal=KILL "$unit"
    printf '\r\nnono-agent: %s が外側で置き換えられ保護が外れたため、セッションを終了しました\r\n終了までに書き換えられた可能性があります。外で git などを使う前に中身を確認してください\r\n' "$lost" >&2
  fi
)
watcher=$!
status=0
systemd-run --user --scope --quiet --collect --unit="$unit" --slice=claude.slice -p OOMPolicy=continue -- \
  bwrap "${mounts[@]}" --die-with-parent --chdir "$cwd" -- \
  perl "$NONO_AGENT_WATCH" "${watched[@]}" -- "${nono_command[@]}" 9<&- 10>&- || status=$?
exec 8>&-
wait "$watcher" || true
[[ ! -t 0 ]] || stty sane
exit "$status"
