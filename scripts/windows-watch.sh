# shellcheck shell=bash

# bin/ime-watch と bin/slack-watch が共有する、Windows 側の常駐の配備と起動停止。
# 呼び出し元は source の前に NAME、ASSEMBLY、DOTNET、CONFIRM_TIMEOUT を決める

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_EXE=${WINDOWS_WATCH_CMD_EXE:-/mnt/c/Windows/System32/cmd.exe}
REG_EXE=${WINDOWS_WATCH_REG_EXE:-/mnt/c/Windows/System32/reg.exe}
TASKLIST_EXE=${WINDOWS_WATCH_TASKLIST_EXE:-/mnt/c/Windows/System32/tasklist.exe}
WSLPATH=${WINDOWS_WATCH_WSLPATH:-/usr/bin/wslpath}
RUN_KEY='HKCU\Software\Microsoft\Windows\CurrentVersion\Run'

# shellcheck source=scripts/windows-profile.sh
source "$repo_dir/scripts/windows-profile.sh"

die() {
  echo "$NAME: $1" >&2
  exit 1
}

# ユーザー名から C:\Users\<name> を組み立てず、Windows が持つ実際のプロファイルを使う。
# C# 側 (SpecialFolder.UserProfile) と WezTerm 側 (%USERPROFILE%) と同じ基準になる
WIN_PROFILE=$(read_userprofile "$CMD_EXE")
[[ -n "$WIN_PROFILE" ]] || die "Windows のユーザープロファイルを特定できません"

PROFILE_DIR=$("$WSLPATH" -u "$WIN_PROFILE")
INSTALL_DIR="$PROFILE_DIR/AppData/Local/$NAME"
WIN_INSTALL_DIR="$WIN_PROFILE\\AppData\\Local\\$NAME"
DLL="$INSTALL_DIR/bin/$ASSEMBLY.dll"
WIN_DLL="$WIN_INSTALL_DIR\\bin\\$ASSEMBLY.dll"
STATE_DIR="$PROFILE_DIR/.cache/$NAME"
STOP_REQUEST="$STATE_DIR/stop.request"
PID_FILE="$STATE_DIR/daemon.pid"
# 常駐は終了処理の途中で PID ファイルを消すので、停止待ちの PID は別に持つ
STOPPING_FILE="$STATE_DIR/stopping.pid"

require_dotnet() {
  [[ -x "$DOTNET" ]] || die "dotnet が見つかりません: $DOTNET"
}

require_installed() {
  [[ -f "$DLL" ]] || die "未インストールです。先に '$NAME install' を実行してください"
}

run_mode() {
  require_dotnet
  require_installed
  "$DOTNET" "$WIN_DLL" "$1"
}

# 常駐はファイル監視で即座に反応し、作成した直後のマーカーを消す。
# 対象へ直接 open すると途中で消えて ENOENT になるので、別名で作って rename する
write_marker() {
  local target=$1 tmp
  tmp="$(dirname "$target")/.$(basename "$target").$$"
  : >"$tmp"
  mv -f "$tmp" "$target"
}

# 停止待ちのプロセスが残っていなければ 1 (停止中)、残っているか不明なら 2 を返す
confirm_stopped() {
  local rc=0
  [[ -f "$STOPPING_FILE" ]] || return 1
  process_state "$(cat "$STOPPING_FILE")" || rc=$?
  ((rc == 1)) || return 2
  rm -f "$STOPPING_FILE"
  return 1
}

# 0: 稼働中、1: 停止中、2: 確認不能。
# 常駐の生死は C# 側に聞く。Windows は PID を使い回すので、PID が生きていることだけでは
# 異常終了直後に PID を拾った別プロセスと区別できない
daemon_state() {
  local output rc=0
  if [[ ! -f "$PID_FILE" ]]; then
    confirm_stopped
    return
  fi
  [[ -f "$DLL" ]] || return 2
  output=$("$DOTNET" "$WIN_DLL" running 2>&1) || rc=$?
  ((rc != 0)) || return 0
  # dotnet ホストの失敗も終了値 1 になりうるが、その場合は必ず理由を出力する
  [[ $rc -eq 1 && -z "$output" ]] || return 2
  confirm_stopped
}

# 0: プロセスがいる、1: いない、2: 確認不能。
# 該当なしでも終了値は 0 で、表示言語によって変わる文を出力する
process_state() {
  local output
  output=$("$TASKLIST_EXE" /FI "PID eq $1" /NH 2>/dev/null) || return 2
  [[ -n "$output" ]] || return 2
  [[ "$output" != *" $1 "* ]] || return 0
  return 1
}

die_unknown() {
  die "常駐の状態を確認できません。プロセスがいなければ $PID_FILE と $STOPPING_FILE を削除してください"
}

cmd_install() {
  local dotnet_win state=0 bin="$INSTALL_DIR/bin" old="$INSTALL_DIR/bin.old" new="$INSTALL_DIR/bin.new"
  require_dotnet
  dotnet_win=$("$WSLPATH" -w "$DOTNET") && [[ -n "$dotnet_win" ]] ||
    die "dotnet のパスを Windows 形式へ変換できません: $DOTNET"

  # 前回の中断の残り。bin.old を残すと、次の rename がその中への移動になる
  if [[ -d "$old" ]]; then
    if [[ -d "$bin" ]]; then
      rm -rf "$old"
    else
      mv "$old" "$bin"
    fi
  fi
  rm -rf "$new"

  mkdir -p "$INSTALL_DIR/src"
  cp "$repo_dir/windows/$NAME/$ASSEMBLY.csproj" "$repo_dir/windows/$NAME/Program.cs" "$INSTALL_DIR/src/"

  # dotnet.exe は Windows のパスしか解釈しないので、出力先も Windows 形式で渡す
  echo "publishing to $new ..."
  (cd "$INSTALL_DIR/src" && "$DOTNET" publish -c Release -o "$WIN_INSTALL_DIR\\bin.new" --nologo)
  [[ -f "$new/$ASSEMBLY.dll" ]] || die "publish しましたが $ASSEMBLY.dll がありません"

  daemon_state || state=$?
  ((state != 2)) || die_unknown
  if ((state == 0)); then
    cmd_stop >/dev/null
  fi

  if [[ -d "$bin" ]] && ! mv "$bin" "$old"; then
    abort_swap "$state"
  fi
  if ! mv "$new" "$bin"; then
    if [[ -d "$old" ]]; then
      mv "$old" "$bin"
    fi
    abort_swap "$state"
  fi

  # ログオン時の自動起動。管理者権限もスクリプトファイルの追加配置も要らないので、
  # schtasks やスタートアップフォルダではなく HKCU の Run キーを使う
  echo "registering autostart ..."
  "$REG_EXE" add "$RUN_KEY" /v "$NAME" /t REG_SZ /f \
    /d "\"$dotnet_win\" \"$WIN_DLL\" watch" >/dev/null ||
    die "新版は配備しましたが、自動起動を登録できません。'$NAME install' を再実行してください"

  rm -rf "$old"
  echo "done. '$NAME start' で起動します"
}

abort_swap() {
  if (($1 == 0)); then
    (cmd_start) || echo "$NAME: 旧版を再起動できません" >&2
  fi
  die "配備先を切り替えられません"
}

cmd_start() {
  local state=0
  require_dotnet
  require_installed

  daemon_state || state=$?
  ((state != 2)) || die_unknown
  if ((state == 0)); then
    echo "already running"
    return
  fi

  # 停止マーカーが残っていると起動直後に自分で消費して終了してしまう
  rm -f "$STOP_REQUEST"

  # UNC を作業ディレクトリにすると cmd/dotnet が警告を出すので Windows 側から起動する。
  # WSL のシェルを抜けても Windows 側のプロセスとして残る
  (cd "$PROFILE_DIR" && setsid "$DOTNET" "$WIN_DLL" watch >/dev/null 2>&1 &)

  local i
  for ((i = 0; i < CONFIRM_TIMEOUT; i++)); do
    sleep 1
    if daemon_state; then
      echo "started"
      return
    fi
  done

  die "起動を確認できません"
}

cmd_stop() {
  local state=0 pid="" i
  if [[ -f "$PID_FILE" ]]; then
    pid=$(cut -d: -f1 "$PID_FILE") || pid=""
  fi
  daemon_state || state=$?
  ((state != 2)) || die_unknown
  if ((state == 1)); then
    # 置きっぱなしのマーカーは次回起動を即終了させるので消す
    rm -f "$STOP_REQUEST" "$PID_FILE"
    echo "not running"
    return
  fi

  if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! process_state "$pid"; then
    die_unknown
  fi

  # 完了の判断はマーカーや PID ファイルの消滅ではなく、プロセスの終了。常駐は PID ファイルを
  # 消した後も Mutex と DLL を持っており、その間は旧版の再起動も配備先の rename も失敗しうる
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$pid" >"$STOPPING_FILE"
  write_marker "$STOP_REQUEST"

  for ((i = 0; i < CONFIRM_TIMEOUT; i++)); do
    sleep 1
    state=0
    process_state "$pid" || state=$?
    if ((state == 1)); then
      rm -f "$STOP_REQUEST" "$PID_FILE" "$STOPPING_FILE"
      echo "stopped"
      return
    fi
  done

  rm -f "$STOP_REQUEST"
  die "停止を確認できません (常駐がまだ動いている可能性があります)"
}
