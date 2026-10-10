package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// このテストバイナリが `pane report-metadata ...` で起動されたら模擬 herdr として
// 振る舞う。子の環境は HERDR_SOCKET_PATH だけなので、記録は cwd に書き、挙動は
// ソケットの basename から読む。
func TestMain(m *testing.M) {
	if len(os.Args) > 2 && os.Args[1] == "pane" && os.Args[2] == "report-metadata" {
		mockHerdr()
	}
	os.Exit(m.Run())
}

type record struct {
	Args []string
	Env  []string
}

func mockHerdr() {
	behavior := filepath.Base(os.Getenv("HERDR_SOCKET_PATH"))
	if behavior == "hang" {
		signal.Ignore(syscall.SIGTERM)
	}
	data, _ := json.Marshal(record{os.Args[1:], os.Environ()})
	f, _ := os.OpenFile("records.jsonl", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	_, _ = f.Write(append(data, '\n'))
	_ = f.Close()
	switch behavior {
	case "fail":
		os.Stdout.WriteString("herdr stdout\n")
		os.Stderr.WriteString("herdr stderr\n")
		os.Exit(3)
	case "hang":
		time.Sleep(10 * time.Second)
	}
	os.Exit(0)
}

// fixedNow は 2026-10-10T00:00:10Z。userLine/assistantLine の時刻はこれより前に置く。
var fixedNow = time.Date(2026, 10, 10, 0, 0, 10, 0, time.UTC)

type harness struct {
	h       *hook
	clock   time.Time
	reports [][]string
	// onSleep はポーリングの待ちごとに呼ばれる。遅れて届くエントリを書くのに使う。
	onSleep func(n int)
	sleeps  int
	dir     string
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	hs := &harness{clock: fixedNow, dir: t.TempDir()}
	hs.h = &hook{
		sessionID: sid,
		path:      filepath.Join(hs.dir, "state", "p1-s1.json"),
		now:       func() time.Time { return hs.clock },
		sleep: func(d time.Duration) {
			hs.clock = hs.clock.Add(d)
			hs.sleeps++
			if hs.onSleep != nil {
				hs.onSleep(hs.sleeps)
			}
		},
		loc:    time.FixedZone("JST", 9*3600),
		report: func(args ...string) { hs.reports = append(hs.reports, args) },
	}
	return hs
}

func (hs *harness) transcript(t *testing.T, lines ...string) string {
	t.Helper()
	path := filepath.Join(hs.dir, "t.jsonl")
	writeFile(t, path, strings.Join(lines, "\n")+"\n")
	return path
}

func (hs *harness) appendLines(t *testing.T, lines ...string) {
	t.Helper()
	f, err := os.OpenFile(filepath.Join(hs.dir, "t.jsonl"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.WriteString(strings.Join(lines, "\n") + "\n"); err != nil {
		t.Fatal(err)
	}
}

func (hs *harness) setState(t *testing.T, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(hs.h.path), 0o700); err != nil {
		t.Fatal(err)
	}
	writeFile(t, hs.h.path, content)
}

// state はディスク上の状態ファイルの中身。ファイルがなければ "absent"。
func (hs *harness) state(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(hs.h.path)
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOTDIR) {
		return "absent"
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func payload(fields string) obj {
	return parseObj([]byte(fields))
}

var clearArgs = []string{"--clear-token", "cache"}

func (hs *harness) expect(t *testing.T, state string, reports ...[]string) {
	t.Helper()
	if !slices.EqualFunc(hs.reports, reports, slices.Equal) {
		t.Errorf("reports:\n got %q\nwant %q", hs.reports, reports)
	}
	if got := hs.state(t); got != state {
		t.Errorf("state: got %s, want %s", got, state)
	}
}

func token(label string, ttlMs int64) []string {
	return []string{"--token", "cache=" + label, "--ttl-ms", strconv.FormatInt(ttlMs, 10)}
}

// turn は 00:00:00Z に開いて 00:00:05Z に 5m のキャッシュを書いたターン。
// 失効は 00:05:00Z (JST 09:05) で、fixedNow からの残りは 290s - 安全マージン。
func turn(mid string) []string {
	return []string{
		userLine("2026-10-10T00:00:00Z"),
		assistantLine(mid, "2026-10-10T00:00:05Z", `"end_turn"`, write5m),
	}
}

func tp(path string) obj {
	return payload(`{"transcript_path":` + strconv.Quote(path) + `}`)
}

func TestStopPublishes(t *testing.T) {
	hs := newHarness(t)
	path := hs.transcript(t, turn("m1")...)
	hs.setState(t, `{"stale_after":1,"ttl":"5m","expires_at":2}`)
	if err := hs.h.stop(tp(path)); err != nil {
		t.Fatal(err)
	}
	hs.expect(t, `{"cursor_mid":"m1"}`, token("~09:05", 288000))
	if hs.sleeps != 0 {
		t.Errorf("polled %d times", hs.sleeps)
	}
}

func TestStopExpiryBoundary(t *testing.T) {
	cases := []struct {
		name  string
		now   time.Time
		state string
		want  []string
	}{
		// 残りが安全マージンちょうどなら clear。cursor は進み、watermark は消える。
		{"remaining equals margin", time.Date(2026, 10, 10, 0, 4, 58, 0, time.UTC), `{"cursor_mid":"m1"}`, clearArgs},
		// 1ms 残りは浮動小数点の誤差で 0 に切り捨てられる。旧実装と同じ式なので結果も同じ。
		{"two milliseconds left", time.Date(2026, 10, 10, 0, 4, 57, 998e6, time.UTC), `{"cursor_mid":"m1"}`, token("~09:05", 2)},
		{"expired", time.Date(2026, 10, 10, 1, 0, 0, 0, time.UTC), `{"cursor_mid":"m1"}`, clearArgs},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			hs := newHarness(t)
			hs.clock = c.now
			path := hs.transcript(t, turn("m1")...)
			hs.setState(t, `{"stale_after":1791590400}`)
			if err := hs.h.stop(tp(path)); err != nil {
				t.Fatal(err)
			}
			hs.expect(t, c.state, c.want)
		})
	}
}

func TestStopWaitsForEntry(t *testing.T) {
	hs := newHarness(t)
	path := hs.transcript(t, turn("m1")...)
	hs.setState(t, `{"cursor_mid":"m1"}`)
	hs.onSleep = func(n int) {
		if n == 3 {
			hs.appendLines(t, userLine("2026-10-10T00:00:06Z"),
				assistantLine("m2", "2026-10-10T00:00:07Z", `"end_turn"`, readOnly))
		}
	}
	if err := hs.h.stop(tp(path)); err != nil {
		t.Fatal(err)
	}
	// 読むだけのターンは m1 の 5m を引き継ぎ、開始は 00:00:06Z。3 回の待ちで 300ms 進む。
	hs.expect(t, `{"cursor_mid":"m2"}`, token("~09:05", 306000-10300-2000))
	if hs.sleeps != 3 {
		t.Errorf("polled %d times", hs.sleeps)
	}
}

func TestStopDeadlineAndRecovery(t *testing.T) {
	hs := newHarness(t)
	path := hs.transcript(t, turn("m1")...)
	hs.setState(t, `{"cursor_mid":"m1"}`)
	if err := hs.h.stop(tp(path)); err != nil {
		t.Fatal(err)
	}
	// 1.5 秒の予算を 100ms ずつ待ち切ってから諦め、その時刻を watermark にする。
	if hs.sleeps != 15 {
		t.Errorf("polled %d times", hs.sleeps)
	}
	hs.expect(t, `{"cursor_mid":"m1","stale_after":1791590411.5}`, clearArgs)

	// 諦めたターンの遅れたエントリは watermark より前の時刻なので採らない。
	hs.reports = nil
	hs.appendLines(t, assistantLine("late", "2026-10-10T00:00:11Z", `"end_turn"`, write5m))
	if err := hs.h.stop(tp(path)); err != nil {
		t.Fatal(err)
	}
	hs.expect(t, `{"cursor_mid":"late","stale_after":1791590413}`, clearArgs)

	// 次の新しいターンは報告され、watermark は消える。
	hs.reports = nil
	hs.appendLines(t, userLine("2026-10-10T00:00:20Z"),
		assistantLine("m3", "2026-10-10T00:00:21Z", `"end_turn"`, write1h))
	if err := hs.h.stop(tp(path)); err != nil {
		t.Fatal(err)
	}
	hs.expect(t, `{"cursor_mid":"m3"}`, token("~10:00", 3620000-13000-2000))
}

func TestStopCursorOutOfWindow(t *testing.T) {
	cases := []struct {
		name  string
		lines []string
		state string
	}{
		{"re-anchors to newest terminal", turn("m1"), `{"cursor_mid":"m1","stale_after":1791590411.5}`},
		{"drops cursor when nothing is terminal", []string{userLine("2026-10-10T00:00:00Z")}, `{"stale_after":1791590411.5}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			hs := newHarness(t)
			path := hs.transcript(t, c.lines...)
			hs.setState(t, `{"cursor_mid":"gone"}`)
			if err := hs.h.stop(tp(path)); err != nil {
				t.Fatal(err)
			}
			hs.expect(t, c.state, clearArgs)
		})
	}
}

func TestStopFailsClosed(t *testing.T) {
	cases := []struct {
		name    string
		payload func(hs *harness) obj
		lines   []string
	}{
		{"missing transcript", func(hs *harness) obj { return tp(filepath.Join(hs.dir, "missing")) }, nil},
		{"no transcript_path", func(*harness) obj { return payload(`{}`) }, nil},
		{"unknown TTL", nil, []string{userLine("2026-10-10T00:00:00Z"), assistantLine("m1", "2026-10-10T00:00:05Z", `"end_turn"`, `{"input_tokens":5}`)}},
		{"no request start", nil, []string{assistantLine("m1", "2026-10-10T00:00:05Z", `"end_turn"`, write5m)}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			hs := newHarness(t)
			var p obj
			if c.payload != nil {
				p = c.payload(hs)
			} else {
				p = tp(hs.transcript(t, c.lines...))
			}
			hs.setState(t, `{"stale_after":1,"ttl":"5m"}`)
			if err := hs.h.stop(p); err != nil {
				t.Fatal(err)
			}
			hs.expect(t, `{"stale_after":1}`, clearArgs)
		})
	}
}

// 存在確認の後で読めなくなった transcript はエラーとして返り、run が clear だけを送る。
func TestStopReadErrorLeavesState(t *testing.T) {
	hs := newHarness(t)
	hs.setState(t, `{"cursor_mid":"m0"}`)
	if err := hs.h.stop(tp(hs.dir)); err == nil {
		t.Fatal("reading a directory did not fail")
	}
	hs.expect(t, `{"cursor_mid":"m0"}`)

	path := hs.transcript(t, turn("m0")...)
	hs.onSleep = func(n int) {
		if n == 2 {
			_ = os.Remove(path)
		}
	}
	if err := hs.h.stop(tp(path)); err == nil {
		t.Fatal("a transcript removed mid-poll did not fail")
	}
	hs.expect(t, `{"cursor_mid":"m0"}`)
}

func TestSession(t *testing.T) {
	cases := []struct {
		name   string
		source string
		want   []string
		state  string
	}{
		{"resume republishes despite the stored cursor", "resume", token("~09:05", 288000), `{"cursor_mid":"m1"}`},
		{"startup republishes", "startup", token("~09:05", 288000), `{"cursor_mid":"m1"}`},
		{"clear", "clear", clearArgs, `{"cursor_mid":"m1","stale_after":1}`},
		{"compact", "compact", clearArgs, `{"cursor_mid":"m1","stale_after":1}`},
		{"unknown source", "other", clearArgs, `{"cursor_mid":"m1","stale_after":1}`},
		{"missing source", "", clearArgs, `{"cursor_mid":"m1","stale_after":1}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			hs := newHarness(t)
			path := hs.transcript(t, turn("m1")...)
			hs.setState(t, `{"cursor_mid":"m1","stale_after":1}`)
			p := tp(path)
			if c.source != "" {
				p["source"] = json.RawMessage(strconv.Quote(c.source))
			}
			if err := hs.h.session(p); err != nil {
				t.Fatal(err)
			}
			hs.expect(t, c.state, c.want)
		})
	}

	t.Run("missing transcript", func(t *testing.T) {
		hs := newHarness(t)
		if err := hs.h.session(payload(`{"source":"resume","transcript_path":"/nonexistent"}`)); err != nil {
			t.Fatal(err)
		}
		hs.expect(t, `{}`, clearArgs)
	})
	t.Run("no terminal entry", func(t *testing.T) {
		hs := newHarness(t)
		path := hs.transcript(t, userLine("2026-10-10T00:00:00Z"))
		p := tp(path)
		p["source"] = json.RawMessage(`"resume"`)
		if err := hs.h.session(p); err != nil {
			t.Fatal(err)
		}
		hs.expect(t, `{}`, clearArgs)
	})
}

func TestCompact(t *testing.T) {
	hs := newHarness(t)
	hs.setState(t, `{"cursor_mid":"m1","stale_after":1.5,"ttl":"5m","expires_at":9}`)
	_ = hs.h.compact(nil)
	hs.expect(t, `{"cursor_mid":"m1","stale_after":1.5}`, clearArgs)

	hs = newHarness(t)
	_ = hs.h.compact(nil)
	hs.expect(t, `{}`, clearArgs)
}

func TestLoadIsFieldwise(t *testing.T) {
	cases := map[string]string{
		`{"cursor_mid":1,"stale_after":"x"}`:     `{}`,
		`{"cursor_mid":"","stale_after":null}`:   `{}`,
		`{"cursor_mid":"m","stale_after":"1"}`:   `{"cursor_mid":"m"}`,
		`{"cursor_mid":null,"stale_after":2.25}`: `{"stale_after":2.25}`,
		`[1]`:                                    `{}`,
		`not json`:                               `{}`,
	}
	for content, want := range cases {
		hs := newHarness(t)
		hs.setState(t, content)
		data, _ := json.Marshal(hs.h.load())
		if string(data) != want {
			t.Errorf("%s: got %s, want %s", content, data, want)
		}
	}
}

func TestSavePermissions(t *testing.T) {
	hs := newHarness(t)
	dir := filepath.Dir(hs.h.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if !hs.h.save(state{CursorMID: "m"}) {
		t.Fatal("save failed")
	}
	for path, want := range map[string]os.FileMode{dir: 0o700, hs.h.path: 0o600} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if got := info.Mode().Perm(); got != want {
			t.Errorf("%s: mode %o, want %o", path, got, want)
		}
	}
}

func TestSaveFailure(t *testing.T) {
	// 保存先のディレクトリを作れなければ、報告はせず clear だけを送る。
	hs := newHarness(t)
	path := hs.transcript(t, turn("m1")...)
	blocker := filepath.Join(hs.dir, "file")
	writeFile(t, blocker, "")
	hs.h.path = filepath.Join(blocker, "p1-s1.json")
	if err := hs.h.stop(tp(path)); err != nil {
		t.Fatal(err)
	}
	hs.expect(t, "absent", clearArgs)

	// failClosed で書けなかった状態は消す。状態ファイルの位置にある空ディレクトリは
	// rename で置き換えられないが、Remove では消える。
	hs = newHarness(t)
	if err := os.MkdirAll(hs.h.path, 0o700); err != nil {
		t.Fatal(err)
	}
	_ = hs.h.compact(nil)
	hs.expect(t, "absent", clearArgs)
}

func TestStatePath(t *testing.T) {
	got := statePath("/home/u", "p:1", "s/../_1 é-x")
	if want := "/home/u/.local/state/herdr-cache-token/p1-s_1-x.json"; got != want {
		t.Errorf("got %s, want %s", got, want)
	}
	if statePath("/h", "p1", "s") == statePath("/h", "p2", "s") {
		t.Error("panes share a state file")
	}
}

// runFixture は run() を模擬 herdr 付きで動かす環境を整える。cwd は記録の置き場。
func runFixture(t *testing.T, behavior string) string {
	t.Helper()
	self, err := filepath.Abs(os.Args[0])
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	t.Chdir(dir)
	t.Setenv("HOME", filepath.Join(dir, "home"))
	t.Setenv("HERDR_ENV", "1")
	t.Setenv("HERDR_PANE_ID", "p1")
	t.Setenv("HERDR_SOCKET_PATH", filepath.Join(dir, behavior))
	t.Setenv("HERDR_BIN_PATH", self)
	return dir
}

func readRecords(t *testing.T, dir string) []record {
	t.Helper()
	f, err := os.Open(filepath.Join(dir, "records.jsonl"))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var out []record
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		var r record
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			t.Fatal(err)
		}
		out = append(out, r)
	}
	return out
}

// fixedArgs は --seq の値を SEQ に置き換えた argv。
func fixedArgs(r record) []string {
	args := slices.Clone(r.Args)
	if len(args) > 6 && args[5] == "--seq" {
		args[6] = "SEQ"
	}
	return args
}

func reportArgs(extra ...string) []string {
	return append([]string{"pane", "report-metadata", "p1", "--source", "claude-cache", "--seq", "SEQ"}, extra...)
}

func TestRunEntryPoint(t *testing.T) {
	type tc struct {
		name  string
		args  []string
		input string
		setup func(t *testing.T)
		want  [][]string
	}
	clearAll := [][]string{reportArgs(clearArgs...)}
	cases := []tc{
		{"outside Herdr", []string{"stop"}, `{}`, func(t *testing.T) { t.Setenv("HERDR_ENV", "0") }, nil},
		{"no pane", []string{"stop"}, `{}`, func(t *testing.T) { t.Setenv("HERDR_PANE_ID", "") }, nil},
		{"invalid JSON", []string{"stop"}, `{"session_id":`, nil, clearAll},
		{"non-object JSON", []string{"stop"}, `["s1"]`, nil, clearAll},
		{"missing session ID", []string{"compact"}, `{"session_id":""}`, nil, clearAll},
		{"missing session ID with unknown action", []string{"bogus"}, `{}`, nil, clearAll},
		{"unknown action", []string{"bogus"}, `{"session_id":"s1"}`, nil, nil},
		{"default action is stop", nil, `{"session_id":"s1","transcript_path":"/nonexistent"}`, nil, clearAll},
		{"BOM-prefixed payload", []string{"compact"}, "\xef\xbb\xbf" + `{"session_id":"s1"}`, nil, clearAll},
		{"HOME unset", []string{"compact"}, `{"session_id":"s1"}`, func(t *testing.T) { t.Setenv("HOME", "") }, clearAll},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := runFixture(t, "ok")
			if c.setup != nil {
				c.setup(t)
			}
			run(c.args, strings.NewReader(c.input))
			var got [][]string
			for _, r := range readRecords(t, dir) {
				got = append(got, fixedArgs(r))
			}
			if !slices.EqualFunc(got, c.want, slices.Equal) {
				t.Errorf("reports:\n got %q\nwant %q", got, c.want)
			}
		})
	}

	// BOM 付きでも session ID を読めていれば、compact は状態ファイルを書く。HOME が
	// なければ何も書かない。
	t.Run("state follows HOME", func(t *testing.T) {
		dir := runFixture(t, "ok")
		run([]string{"compact"}, strings.NewReader("\xef\xbb\xbf"+`{"session_id":"s1"}`))
		if _, err := os.Stat(filepath.Join(dir, "home/.local/state/herdr-cache-token/p1-s1.json")); err != nil {
			t.Error(err)
		}
		t.Setenv("HOME", "")
		run([]string{"compact"}, strings.NewReader(`{"session_id":"s2"}`))
		entries, _ := os.ReadDir(dir)
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		if want := []string{"home", "records.jsonl"}; !slices.Equal(names, want) {
			t.Errorf("files in cwd %q, want %q", names, want)
		}
	})
}

func TestRunPublishes(t *testing.T) {
	dir := runFixture(t, "ok")
	path := filepath.Join(dir, "t.jsonl")
	// 実時間で 5m の寿命が残るよう、直前のターンにする。
	start := time.Now().Add(-time.Second).UTC()
	writeFile(t, path, strings.Join([]string{
		userLine(start.Format(time.RFC3339Nano)),
		assistantLine("m1", start.Format(time.RFC3339Nano), `"end_turn"`, write5m),
	}, "\n")+"\n")
	before := time.Now().UnixNano()
	run([]string{"stop"}, strings.NewReader(`{"session_id":"s1","transcript_path":`+strconv.Quote(path)+`}`))
	after := time.Now().UnixNano()

	records := readRecords(t, dir)
	if len(records) != 1 {
		t.Fatalf("records %+v", records)
	}
	r := records[0]
	if seq, err := strconv.ParseInt(r.Args[6], 10, 64); err != nil || seq < before || seq > after {
		t.Errorf("seq %q is not epoch nanoseconds within [%d, %d]", r.Args[6], before, after)
	}
	label := "~" + start.Add(5*time.Minute).In(time.Local).Format("15:04")
	got := fixedArgs(r)
	if len(got) != 11 || !slices.Equal(got[:9], reportArgs("--token", "cache="+label)) || got[9] != "--ttl-ms" {
		t.Fatalf("args %q", got)
	}
	if ttlMs, _ := strconv.Atoi(got[10]); ttlMs < 290000 || ttlMs > 297000 {
		t.Errorf("ttl-ms %d", ttlMs)
	}
	if want := []string{"HERDR_SOCKET_PATH=" + filepath.Join(dir, "ok")}; !slices.Equal(r.Env, want) {
		t.Errorf("env %q, want %q", r.Env, want)
	}
}

func TestHerdrExecution(t *testing.T) {
	t.Run("absent socket variable is not invented", func(t *testing.T) {
		dir := runFixture(t, "ok")
		os.Unsetenv("HERDR_SOCKET_PATH")
		herdr("p1", time.Now)("--clear-token", "cache")
		if r := readRecords(t, dir); len(r) != 1 || len(r[0].Env) != 0 {
			t.Errorf("records %+v", r)
		}
	})
	t.Run("empty socket variable is forwarded", func(t *testing.T) {
		dir := runFixture(t, "ok")
		t.Setenv("HERDR_SOCKET_PATH", "")
		herdr("p1", time.Now)("--clear-token", "cache")
		if r := readRecords(t, dir); len(r) != 1 || !slices.Equal(r[0].Env, []string{"HERDR_SOCKET_PATH="}) {
			t.Errorf("records %+v", r)
		}
	})
	t.Run("PATH lookup", func(t *testing.T) {
		dir := runFixture(t, "ok")
		bin := filepath.Join(dir, "bin")
		if err := os.Mkdir(bin, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(os.Getenv("HERDR_BIN_PATH"), filepath.Join(bin, "herdr")); err != nil {
			t.Fatal(err)
		}
		t.Setenv("PATH", bin)
		t.Setenv("HERDR_BIN_PATH", "")
		herdr("p1", time.Now)("--clear-token", "cache")
		if r := readRecords(t, dir); len(r) != 1 {
			t.Errorf("records %+v", r)
		}
	})
	t.Run("missing executable", func(t *testing.T) {
		dir := runFixture(t, "ok")
		t.Setenv("HERDR_BIN_PATH", filepath.Join(dir, "missing"))
		herdr("p1", time.Now)("--clear-token", "cache")
		if r := readRecords(t, dir); len(r) != 0 {
			t.Errorf("records %+v", r)
		}
	})
	t.Run("nonzero exit", func(t *testing.T) {
		dir := runFixture(t, "fail")
		herdr("p1", time.Now)("--clear-token", "cache")
		if r := readRecords(t, dir); len(r) != 1 {
			t.Errorf("records %+v", r)
		}
	})
	t.Run("timeout kills a herdr that ignores SIGTERM", func(t *testing.T) {
		runFixture(t, "hang")
		saved := herdrTimeout
		herdrTimeout = 300 * time.Millisecond
		t.Cleanup(func() { herdrTimeout = saved })
		start := time.Now()
		herdr("p1", time.Now)("--clear-token", "cache")
		if elapsed := time.Since(start); elapsed > 3*time.Second {
			t.Errorf("took %v", elapsed)
		}
	})
}
