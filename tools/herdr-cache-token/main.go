// herdr-cache-token は Claude Code の pane の prompt cache の失効時刻を、Herdr の
// $cache トークンとして報告するフック。
//
//	herdr-cache-token [stop|session|compact]
//
// Claude Code はキャッシュの寿命を公開しないので transcript から導く。選んだ
// assistant メッセージの usage が書かれた TTL を示し、その直前の user エントリの
// 時刻をリクエスト開始の代わりに使う。
//
// トークンは残り寿命を --ttl-ms に付けて登録するので、Herdr はキャッシュの失効と
// 同時にトークンを消す。$cache がないことは「再利用できるキャッシュがない」を意味し、
// カウントダウンするものは何もない。
//
// 表示専用のフックなので、何が起きても何も出力せず exit 0 で終わる。
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"
)

const (
	// Herdr は pane のメタデータを source ごとに持つので、この文字列を変えてはならない。
	source    = "claude-cache"
	tokenName = "cache"
	budget    = 1500 * time.Millisecond
	interval  = 100 * time.Millisecond
	// トークンはキャッシュより少し先に消えるべきで、後に残ってはならない。
	safetyMs = 2000
)

// 期限を過ぎたら CommandContext の既定どおり SIGKILL する。SIGTERM を無視する
// herdr を待ってターンの終了を遅らせないため。テストが短くできるよう変数にしている。
var herdrTimeout = 5 * time.Second

// state はターンの境界だけを持つ。TTL や失効時刻は毎回 transcript から導くので、
// 旧版が書いた ttl や expires_at は読み込み時に捨てる。
type state struct {
	CursorMID  string   `json:"cursor_mid,omitempty"`
	StaleAfter *float64 `json:"stale_after,omitempty"`
}

type hook struct {
	sessionID string
	path      string // 状態ファイル
	now       func() time.Time
	sleep     func(time.Duration)
	loc       *time.Location
	// report は herdr pane report-metadata に source と seq より後ろの引数を渡す。
	report func(args ...string)
}

// epochNow は旧実装の Date.now() / 1000 と同じミリ秒精度の epoch 秒。
func (h *hook) epochNow() float64 {
	return float64(h.now().UnixMilli()) / 1000
}

// load は状態をフィールドごとに読む。形の合わない値は比較に持ち込まずに捨てる。
// stale_after: null を 0 として扱うと鮮度の判定が黙って無効になる。
func (h *hook) load() state {
	var st state
	data, err := os.ReadFile(h.path)
	if err != nil {
		return st
	}
	o := parseObj(data)
	st.CursorMID = o.str("cursor_mid")
	if stale, ok := o.number("stale_after"); ok {
		st.StaleAfter = &stale
	}
	return st
}

// save は状態がディスクに届いたときだけ true を返す。
func (h *hook) save(st state) bool {
	dir := filepath.Dir(h.path)
	if os.MkdirAll(dir, 0o700) != nil || os.Chmod(dir, 0o700) != nil {
		return false
	}
	data, err := json.Marshal(st)
	if err != nil {
		return false
	}
	tmp := fmt.Sprintf("%s.%d.tmp", h.path, os.Getpid())
	return os.WriteFile(tmp, data, 0o600) == nil && os.Rename(tmp, h.path) == nil
}

func (h *hook) clear() {
	h.report("--clear-token", tokenName)
}

// failClosed はトークンを消し、呼び出し側が整えた状態を書く。書けない状態は
// 残してはならないので、そのときはファイルごと消す。
func (h *hook) failClosed(st state) {
	h.clear()
	if !h.save(st) {
		_ = os.Remove(h.path)
	}
}

func (h *hook) reportExpiry(expiresAt float64) {
	remaining := int64(math.Trunc((expiresAt-h.epochNow())*1000)) - safetyMs
	if remaining <= 0 {
		h.clear()
		return
	}
	label := "~" + time.UnixMilli(int64(math.Trunc(expiresAt*1000))).In(h.loc).Format("15:04")
	h.report("--token", tokenName+"="+label, "--ttl-ms", strconv.FormatInt(remaining, 10))
}

// publish は 1 つの assistant メッセージから失効時刻を導いてトークンを登録する。
func (h *hook) publish(st state, objs []obj, groups []*group, idx int) {
	seconds := ttl(groups, idx)
	start, ok := requestStart(objs, groups[idx], h.sessionID)
	if seconds == 0 || !ok {
		h.failClosed(st)
		return
	}
	// cursor を残せなければ、次の Stop がこのエントリを拾い直しうる。
	if !h.save(state{CursorMID: groups[idx].mid}) {
		h.clear()
		return
	}
	h.reportExpiry(start + float64(seconds))
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// stop はターンの完了後に、cursor より後の新しい完了エントリを選んで報告する。
func (h *hook) stop(payload obj) error {
	path := payload.str("transcript_path")
	st := h.load()
	if path == "" || !exists(path) {
		h.failClosed(st)
		return nil
	}

	deadline := h.now().Add(budget)
	var objs []obj
	var groups []*group
	idx := -1
	for {
		var err error
		if objs, err = readTail(path); err != nil {
			return err
		}
		groups = groupAssistants(objs, h.sessionID)
		idx = newestTerminal(groups, st.CursorMID, st.StaleAfter)
		if idx >= 0 || !h.now().Before(deadline) {
			break
		}
		h.sleep(interval)
	}

	if idx < 0 {
		// ターンが届かなかったか、cursor が窓から外れた。ここで何かを報告すると嘘に
		// なる。次のターンが回復できるよう境界を張り直し、遅れて届くこのターンの
		// エントリを次のターンのものと取り違えないよう、諦めた時刻を残す。
		// 窓に完了エントリがなければ見つからない cursor は捨て、鮮度は stale_after に任せる。
		st.CursorMID = ""
		if newest := newestTerminal(groups, "", nil); newest >= 0 {
			st.CursorMID = groups[newest].mid
		}
		now := h.epochNow()
		st.StaleAfter = &now
		h.failClosed(st)
		return nil
	}
	h.publish(st, objs, groups, idx)
	return nil
}

// session は SessionStart で transcript からトークンを導き直すか、消す。Herdr は
// サーバーの再起動で pane のメタデータを失うので、ここで登録し直す。保存した
// 失効時刻から戻さないのは、それを正当化した状態より長く残りうるため。
func (h *hook) session(payload obj) error {
	path := payload.str("transcript_path")
	st := h.load()
	// clear と compact はプレフィックスを捨てる。不明な source もキャッシュが
	// 残っている証拠にならないので消す。
	resuming := payload.str("source") == "startup" || payload.str("source") == "resume"
	if !resuming || path == "" || !exists(path) {
		h.failClosed(st)
		return nil
	}
	objs, err := readTail(path)
	if err != nil {
		return err
	}
	groups := groupAssistants(objs, h.sessionID)
	idx := newestTerminal(groups, "", nil)
	if idx < 0 {
		h.failClosed(st)
		return nil
	}
	h.publish(st, objs, groups, idx)
	return nil
}

// compact はプレフィックスを書き換えるので、キャッシュには届かなくなる。
func (h *hook) compact(obj) error {
	h.failClosed(h.load())
	return nil
}

// herdr は報告を best effort で送る。子には HERDR_SOCKET_PATH だけを渡す。
func herdr(pane string, now func() time.Time) func(args ...string) {
	return func(args ...string) {
		// Herdr は自分の store パスを HERDR_BIN_PATH で渡す。素の名前より優先すると、
		// home-manager switch がプロファイルを入れ替えている最中もフックが動く。
		name := os.Getenv("HERDR_BIN_PATH")
		if name == "" {
			name = "herdr"
		}
		bin, err := exec.LookPath(name)
		if err != nil {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), herdrTimeout)
		defer cancel()
		full := append([]string{
			"pane", "report-metadata", pane,
			"--source", source,
			"--seq", strconv.FormatInt(now().UnixNano(), 10),
		}, args...)
		cmd := exec.CommandContext(ctx, bin, full...)
		// nil だと親の環境をすべて引き継ぐので、空でも nil でないスライスにする。
		cmd.Env = []string{}
		if socket, ok := os.LookupEnv("HERDR_SOCKET_PATH"); ok {
			cmd.Env = append(cmd.Env, "HERDR_SOCKET_PATH="+socket)
		}
		_ = cmd.Run()
	}
}

func run(args []string, stdin io.Reader) {
	action := "stop"
	if len(args) > 0 {
		action = args[0]
	}
	pane := os.Getenv("HERDR_PANE_ID")
	if os.Getenv("HERDR_ENV") != "1" || pane == "" {
		return
	}

	h := &hook{
		now:   time.Now,
		sleep: time.Sleep,
		loc:   time.Local,
	}
	h.report = herdr(pane, h.now)

	// 旧実装は TextDecoder で読んでいたので、先頭の BOM を受け付けていた。
	input, _ := io.ReadAll(stdin)
	payload := parseObj(bytes.TrimPrefix(input, []byte("\xef\xbb\xbf")))

	// セッション ID がなければ transcript をこの会話に絞れず、キャッシュについて
	// 言えることがない。
	h.sessionID = payload.str("session_id")
	if h.sessionID == "" {
		h.clear()
		return
	}

	handlers := map[string]func(obj) error{
		"stop":    h.stop,
		"session": h.session,
		"compact": h.compact,
	}
	handler, ok := handlers[action]
	if !ok {
		return
	}
	// 旧ランチャーは Deno の許可リストを $HOME から組んでいたので、HOME がないと
	// transcript も状態も読み書きできず、結果は clear だけだった。
	home := os.Getenv("HOME")
	if home == "" {
		h.clear()
		return
	}
	h.path = statePath(home, pane, h.sessionID)

	if err := handler(payload); err != nil {
		// 正当化できなくなったトークンを残さない。状態には触れない。
		h.clear()
	}
}

// statePath はセッションだけでなく pane でも分ける。同じセッションを 2 つの pane で
// 再開すると、それぞれが独立した $cache トークンを持ち、cursor を共有してはならない。
func statePath(home, pane, sessionID string) string {
	var safe []byte
	for _, c := range []byte(pane + "-" + sessionID) {
		if 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9' || c == '-' || c == '_' {
			safe = append(safe, c)
		}
	}
	return filepath.Join(home, ".local/state/herdr-cache-token", string(safe)+".json")
}

func main() {
	run(os.Args[1:], os.Stdin)
}
