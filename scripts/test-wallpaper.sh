#!/usr/bin/env bash
# test-wallpaper.sh — bin/wallpaper の選択と desktoppr 呼び出しを検証する。
# fzf と desktoppr をスタブにし、画像だけが候補に並ぶこと、選んだ画像が絶対パスで
# desktoppr に渡ること、キャンセルや画像なしで desktoppr を呼ばないことを見る。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wallpaper="$repo_root/bin/wallpaper"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

stub_dir="$tmp/bin"
mkdir -p "$stub_dir"
# fzf は受け取った候補を記録し、STUB_FZF_PICK を選んだことにして STUB_FZF_RC で終わる
cat >"$stub_dir/fzf" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_LOG_DIR/fzf-args"
cat >"$STUB_LOG_DIR/fzf-input"
[[ -n ${STUB_FZF_PICK-} ]] && printf '%s\n' "$STUB_FZF_PICK"
exit "${STUB_FZF_RC:-0}"
STUB
cat >"$stub_dir/desktoppr" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_LOG_DIR/desktoppr-args"
STUB
# wezterm は spawn の引数を記録し、STUB_WEZTERM_RC で終わる
cat >"$stub_dir/wezterm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_LOG_DIR/wezterm-args"
exit "${STUB_WEZTERM_RC:-0}"
STUB
chmod +x "$stub_dir/fzf" "$stub_dir/desktoppr" "$stub_dir/wezterm"

failures=0
pass() { echo "  PASS $1"; }
fail() {
  echo "  FAIL $1" >&2
  failures=$((failures + 1))
}

walls="$tmp/walls"
mkdir -p "$walls"
touch "$walls/b.png" "$walls/a.JPG" "$walls/c.heic" "$walls/notes.txt"

run_wallpaper() {
  rm -f "$tmp/fzf-args" "$tmp/fzf-input" "$tmp/desktoppr-args" "$tmp/wezterm-args"
  local rc=0
  # テスト自体を herdr の中で走らせても結果が変わらないよう、端末の判定を空にしておく
  PATH="$stub_dir:$PATH" STUB_LOG_DIR="$tmp" TERM_PROGRAM='' WALLPAPER_SPAWNED='' \
    "$@" "$wallpaper" 2>/dev/null || rc=$?
  return "$rc"
}

# 選んだ画像を絶対パスで渡す
if run_wallpaper env WALLPAPER_DIR="$walls" STUB_FZF_PICK=b.png &&
  [[ "$(cat "$tmp/desktoppr-args")" == "$walls/b.png" ]]; then
  pass "passes the chosen image to desktoppr as an absolute path"
else
  fail "desktoppr args: $(cat "$tmp/desktoppr-args" 2>/dev/null || echo '<not called>')"
fi

# 画像以外は候補に出さず、拡張子の大文字小文字は区別しない
if [[ "$(cat "$tmp/fzf-input")" == $'a.JPG\nb.png\nc.heic' ]]; then
  pass "lists only images, sorted, case-insensitive extensions"
else
  fail "fzf input: $(tr '\n' ' ' <"$tmp/fzf-input")"
fi

# herdr の中では WezTerm のタブへ移り、フォルダを絶対パスで渡す
if run_wallpaper env WALLPAPER_DIR="$walls" TERM_PROGRAM=herdr &&
  [[ ! -e "$tmp/fzf-input" ]] &&
  [[ "$(cat "$tmp/wezterm-args")" == $'cli\nspawn\n--\n/usr/bin/env\nWALLPAPER_SPAWNED=1\nWALLPAPER_DIR='"$walls"$'\n/bin/zsh\n-l\n-c\nwallpaper' ]]; then
  pass "hands off to a new WezTerm tab inside herdr"
else
  fail "herdr hand-off: $(tr '\n' ' ' <"$tmp/wezterm-args" 2>/dev/null || echo '<not called>')"
fi

# 移った先のタブでは移り直さない
if run_wallpaper env WALLPAPER_DIR="$walls" STUB_FZF_RC=130 TERM_PROGRAM=herdr WALLPAPER_SPAWNED=1 &&
  [[ ! -e "$tmp/wezterm-args" ]] && grep -qF -- 'chafa --size=' "$tmp/fzf-args"; then
  pass "does not spawn again from the spawned tab"
else
  fail "spawned tab spawned again or changed the preview format"
fi

# WezTerm へ移れなければ、herdr の中でもプレビューを文字で描く
run_wallpaper env WALLPAPER_DIR="$walls" STUB_FZF_RC=130 TERM_PROGRAM=herdr STUB_WEZTERM_RC=1 || true
if grep -qF -- 'chafa --format=symbols --size=' "$tmp/fzf-args"; then
  pass "falls back to chafa symbols output when the spawn fails"
else
  fail "herdr fallback preview: $(grep -F -- '--preview' -A1 "$tmp/fzf-args" 2>/dev/null | tail -1)"
fi
run_wallpaper env WALLPAPER_DIR="$walls" STUB_FZF_RC=130 TERM_PROGRAM=WezTerm || true
if grep -qF -- 'chafa --size=' "$tmp/fzf-args"; then
  pass "lets chafa pick the format outside herdr"
else
  fail "non-herdr preview: $(grep -F -- '--preview' -A1 "$tmp/fzf-args" | tail -1)"
fi

# Esc / Ctrl-C と 0 件確定は成功扱いで、desktoppr を呼ばない
for rc in 130 1; do
  if run_wallpaper env WALLPAPER_DIR="$walls" STUB_FZF_RC=$rc && [[ ! -e "$tmp/desktoppr-args" ]]; then
    pass "fzf exit $rc exits 0 without calling desktoppr"
  else
    fail "fzf exit $rc was not treated as a no-op"
  fi
done

# fzf 自体のエラーはそのまま返す
rc=0
run_wallpaper env WALLPAPER_DIR="$walls" STUB_FZF_RC=2 || rc=$?
if [[ $rc -eq 2 && ! -e "$tmp/desktoppr-args" ]]; then
  pass "fzf error propagates its exit code"
else
  fail "fzf error returned $rc"
fi

# 画像がない / フォルダがない
mkdir -p "$tmp/empty"
for d in "$tmp/empty" "$tmp/missing"; do
  rc=0
  run_wallpaper env WALLPAPER_DIR="$d" || rc=$?
  if [[ $rc -eq 1 && ! -e "$tmp/fzf-input" ]]; then
    pass "fails before fzf for $(basename "$d") folder"
  else
    fail "$(basename "$d") folder returned $rc"
  fi
done

if ((failures)); then
  echo "test-wallpaper: $failures failure(s)" >&2
  exit 1
fi
echo "test-wallpaper: all passed"
