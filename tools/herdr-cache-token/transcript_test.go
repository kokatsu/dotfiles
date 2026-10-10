package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const sid = "s1"

func userLine(ts string) string {
	return fmt.Sprintf(`{"type":"user","sessionId":%q,"timestamp":%q}`, sid, ts)
}

// assistantLine は 1 つの content block の行。usage は JSON オブジェクトをそのまま埋め込む。
func assistantLine(mid, ts, stop, usage string) string {
	return fmt.Sprintf(`{"type":"assistant","sessionId":%q,"timestamp":%q,"message":{"id":%q,"stop_reason":%s,"usage":%s}}`,
		sid, ts, mid, stop, usage)
}

const (
	write5m  = `{"input_tokens":5,"cache_creation_input_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":10}}`
	write1h  = `{"input_tokens":5,"cache_creation_input_tokens":10,"cache_creation":{"ephemeral_1h_input_tokens":10}}`
	readOnly = `{"input_tokens":5,"cache_read_input_tokens":100}`
)

func objsOf(t *testing.T, lines ...string) []obj {
	t.Helper()
	var objs []obj
	for _, l := range lines {
		o := parseObj([]byte(l))
		if o == nil {
			t.Fatalf("bad fixture line %s", l)
		}
		objs = append(objs, o)
	}
	return objs
}

func TestGroupAssistants(t *testing.T) {
	objs := objsOf(t,
		assistantLine("m1", "2026-10-10T00:00:01Z", "null", `{"input_tokens":1}`),
		assistantLine("m1", "2026-10-10T00:00:02Z", `"end_turn"`, `{"input_tokens":2}`),
		// 後の行の空 stop_reason と オブジェクトでない usage は前の値を消さない。
		assistantLine("m1", "2026-10-10T00:00:03Z", `""`, `null`),
		`{"type":"assistant","sessionId":"other","message":{"id":"m2","stop_reason":"end_turn"}}`,
		`{"type":"assistant","sessionId":"s1","isSidechain":true,"message":{"id":"m3"}}`,
		`{"type":"assistant","sessionId":"s1","isSidechain":null,"message":{"id":"m4"}}`,
		`{"type":"assistant","sessionId":"s1","isSidechain":"false","message":{"id":"m5"}}`,
		`{"type":"assistant","sessionId":"s1","isSidechain":false,"message":{"id":"m6"}}`,
		`{"type":"assistant","sessionId":"s1","message":{"id":""}}`,
		`{"type":"assistant","sessionId":"s1","message":"m7"}`,
		`{"type":"assistant","sessionId":"s1"}`,
		`{"type":"Assistant","sessionId":"s1","message":{"id":"m8"}}`,
	)
	groups := groupAssistants(objs, sid)
	var mids []string
	for _, g := range groups {
		mids = append(mids, g.mid)
	}
	if want := []string{"m1", "m6"}; !slices.Equal(mids, want) {
		t.Fatalf("mids %q, want %q", mids, want)
	}
	m1 := groups[0]
	if m1.firstIdx != 0 || m1.stopReason != "end_turn" || m1.usage.count("input_tokens") != 2 {
		t.Errorf("m1 = %+v", m1)
	}
	if want, _ := objs[0].epoch("timestamp"); !m1.hasTS || m1.ts != want {
		t.Errorf("m1 ts %v, want the first block's %v", m1.ts, want)
	}
}

func TestEpoch(t *testing.T) {
	ts := func(s string) obj { return parseObj([]byte(fmt.Sprintf(`{"t":%q}`, s))) }
	base, ok := ts("2026-10-10T01:00:00.123Z").epoch("t")
	if !ok || base != 1791594000.123 {
		t.Fatalf("base = %v %v", base, ok)
	}
	for _, s := range []string{"2026-10-10T10:00:00.123+09:00", "2026-10-10T01:00:00.123456789Z"} {
		if got, ok := ts(s).epoch("t"); !ok || got != base {
			t.Errorf("%s = %v %v, want %v", s, got, ok, base)
		}
	}
	for _, raw := range []string{`{"t":"yesterday"}`, `{"t":""}`, `{"t":1791594000}`, `{"t":null}`, `{}`} {
		if got, ok := parseObj([]byte(raw)).epoch("t"); ok {
			t.Errorf("%s parsed as %v", raw, got)
		}
	}
}

func TestCount(t *testing.T) {
	o := parseObj([]byte(`{"a":3,"b":0,"c":-1,"d":"4","e":null,"f":1e400,"g":true}`))
	for key, want := range map[string]float64{"a": 3, "b": 0, "c": 0, "d": 0, "e": 0, "f": 0, "g": 0, "missing": 0} {
		if got := o.count(key); got != want {
			t.Errorf("%s = %v, want %v", key, got, want)
		}
	}
}

func TestNewestTerminal(t *testing.T) {
	line := func(mid, ts, stop, usage string) string { return assistantLine(mid, ts, stop, usage) }
	groups := groupAssistants(objsOf(t,
		line("a", "2026-10-10T00:00:01Z", `"end_turn"`, write5m),
		line("b", "2026-10-10T00:00:02Z", `"end_turn"`, `{"input_tokens":0,"cache_read_input_tokens":0}`),
		line("c", "2026-10-10T00:00:03Z", `"tool_use"`, write5m),
		line("d", "2026-10-10T00:00:04Z", `"pause_turn"`, write5m),
		line("e", "2026-10-10T00:00:05Z", `"end_turn"`, readOnly),
		line("f", "bad", `"end_turn"`, write5m),
		line("g", "2026-10-10T00:00:07Z", "null", write5m),
	), sid)
	f := func(v float64) *float64 { return &v }
	cases := []struct {
		name   string
		cursor string
		stale  *float64
		want   string
	}{
		{"newest usable", "", nil, "f"},
		{"after cursor", "a", nil, "f"},
		{"cursor at the last terminal", "f", nil, ""},
		{"cursor absent from window", "zzz", nil, ""},
		{"watermark skips untimed", "", f(0), "e"},
		{"timestamp equal to watermark", "", f(1791590405), ""},
		{"just after watermark", "", f(1791590404.999), "e"},
	}
	for _, c := range cases {
		idx := newestTerminal(groups, c.cursor, c.stale)
		got := ""
		if idx >= 0 {
			got = groups[idx].mid
		}
		if got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

func TestTTL(t *testing.T) {
	cases := []struct {
		name  string
		prior []string
		usage string
		want  int
	}{
		{"5m", nil, write5m, 300},
		{"1h", nil, write1h, 3600},
		{"both positive picks 5m", nil, `{"cache_creation_input_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":4,"ephemeral_1h_input_tokens":6}}`, 300},
		{"read-only inherits newest write", []string{write5m, write1h, readOnly}, readOnly, 3600},
		{"read-only without prior write", []string{readOnly}, readOnly, 0},
		{"total without breakdown", []string{write5m}, `{"cache_read_input_tokens":1,"cache_creation_input_tokens":10}`, 0},
		{"breakdown without total", []string{write5m}, `{"cache_read_input_tokens":1,"cache_creation":{"ephemeral_5m_input_tokens":10}}`, 0},
		{"cache untouched", []string{write5m}, `{"input_tokens":5}`, 0},
		{"iterations ignored", nil, `{"cache_creation_input_tokens":10,"cache_creation":{"ephemeral_1h_input_tokens":10},"iterations":[{"cache_creation":{"ephemeral_5m_input_tokens":3}}]}`, 3600},
	}
	for _, c := range cases {
		var lines []string
		for i, u := range c.prior {
			lines = append(lines, assistantLine(fmt.Sprint("p", i), "2026-10-10T00:00:00Z", `"end_turn"`, u))
		}
		lines = append(lines, assistantLine("x", "2026-10-10T00:00:00Z", `"end_turn"`, c.usage))
		groups := groupAssistants(objsOf(t, lines...), sid)
		if got := ttl(groups, len(groups)-1); got != c.want {
			t.Errorf("%s: got %d, want %d", c.name, got, c.want)
		}
	}
}

func TestRequestStart(t *testing.T) {
	cases := []struct {
		name   string
		before []string
		want   string
	}{
		{"nearest user", []string{userLine("2026-10-10T00:00:01Z"), userLine("2026-10-10T00:00:02Z")}, "2026-10-10T00:00:02Z"},
		{"skips sidechain and other sessions", []string{
			userLine("2026-10-10T00:00:01Z"),
			`{"type":"user","sessionId":"s1","isSidechain":true,"timestamp":"2026-10-10T00:00:02Z"}`,
			`{"type":"user","sessionId":"other","timestamp":"2026-10-10T00:00:03Z"}`,
		}, "2026-10-10T00:00:01Z"},
		{"does not borrow an older time", []string{userLine("2026-10-10T00:00:01Z"), `{"type":"user","sessionId":"s1"}`}, ""},
		{"no user", nil, ""},
	}
	for _, c := range cases {
		objs := objsOf(t, append(c.before, assistantLine("m", "2026-10-10T00:00:09Z", `"end_turn"`, write5m))...)
		groups := groupAssistants(objs, sid)
		got, ok := requestStart(objs, groups[0], sid)
		if c.want == "" {
			if ok {
				t.Errorf("%s: got %v", c.name, got)
			}
			continue
		}
		want, _ := parseObj([]byte(fmt.Sprintf(`{"t":%q}`, c.want))).epoch("t")
		if !ok || got != want {
			t.Errorf("%s: got %v %v, want %v", c.name, got, ok, want)
		}
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestReadTail(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "t.jsonl")
	mids := func(objs []obj) []string {
		var out []string
		for _, o := range objs {
			out = append(out, o.str("id"))
		}
		return out
	}

	writeFile(t, path, "{\"id\":\"a\"}\n\n  \nnot json\n[1]\n{\"id\":\"b\"}\n{\"id\":\"partial")
	objs, err := readTail(path)
	if err != nil || !slices.Equal(mids(objs), []string{"a", "b"}) {
		t.Errorf("small file: %q %v", mids(objs), err)
	}

	// 窓の先頭にかかる行は、行頭から始まっていても捨てる。
	long := `{"id":"long","pad":"` + strings.Repeat("x", 200*1024) + `"}`
	filler := `{"id":"cut","pad":"` + strings.Repeat("y", tailBytes) + `"}`
	writeFile(t, path, filler+"\n"+long+"\n"+`{"id":"last"}`+"\n")
	objs, err = readTail(path)
	if err != nil || !slices.Equal(mids(objs), []string{"long", "last"}) {
		t.Errorf("large file: %q %v", mids(objs), err)
	}

	writeFile(t, path, `{"id":"only","pad":"`+strings.Repeat("z", tailBytes)+`"}`)
	if objs, err = readTail(path); err != nil || len(objs) != 0 {
		t.Errorf("no complete line: %q %v", mids(objs), err)
	}

	if _, err := readTail(filepath.Join(dir, "missing")); err == nil {
		t.Error("missing file: no error")
	}
	if _, err := readTail(dir); err == nil {
		t.Error("directory: no error")
	}
}
