package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// 報告は子プロセスの環境を HERDR_SOCKET_PATH だけに絞るので、模擬 herdr への指示は
// その値で渡す。basename がこの接頭辞で始まれば、このテストバイナリが模擬 herdr として
// 振る舞い、残りの部分を挙動として読む。
const mockSocketPrefix = "mock-herdr-"

// RUN_HOOK が設定されたテストバイナリはフック本体として振る舞う。フック自身の
// 出力と終了コードを見るため。
const runHookEnv = "REPORT_AGENT_SESSION_RUN_HOOK"

func TestMain(m *testing.M) {
	if os.Getenv(runHookEnv) != "" {
		run([]string{"session", os.Getenv(runHookEnv)}, os.Stdin)
		os.Exit(0)
	}
	if socket := os.Getenv("HERDR_SOCKET_PATH"); strings.HasPrefix(filepath.Base(socket), mockSocketPrefix) {
		mockHerdr(socket)
	}
	os.Exit(m.Run())
}

type record struct {
	Args []string
	Env  []string
}

func mockHerdr(socket string) {
	if strings.TrimPrefix(filepath.Base(socket), mockSocketPrefix) == "hang" {
		signal.Ignore(syscall.SIGTERM)
	}
	data, _ := json.Marshal(record{os.Args[1:], os.Environ()})
	_ = os.WriteFile(filepath.Join(filepath.Dir(socket), "record.json"), data, 0o600)
	switch strings.TrimPrefix(filepath.Base(socket), mockSocketPrefix) {
	case "fail":
		os.Stdout.WriteString("herdr stdout\n")
		os.Stderr.WriteString("herdr stderr\n")
		os.Exit(3)
	case "hang":
		time.Sleep(10 * time.Second)
	}
	os.Exit(0)
}

func base(agent, sessionID string) []string {
	return []string{
		"pane", "report-agent-session", "p1",
		"--source", "herdr:" + agent,
		"--agent", agent,
		"--seq", "42",
		"--agent-session-id", sessionID,
	}
}

func TestReportArgs(t *testing.T) {
	claude := func(extra ...string) []string { return append(base("claude", "s1"), extra...) }
	codex := func(extra ...string) []string { return append(base("codex", "s1"), extra...) }
	cases := []struct {
		name  string
		agent string
		input string
		want  []string
	}{
		{"claude SessionStart", "claude", `{"session_id":"s1","hook_event_name":"SessionStart","transcript_path":"/t.jsonl","source":"startup"}`,
			claude("--agent-session-path", "/t.jsonl", "--session-start-source", "startup")},
		{"claude no event", "claude", `{"session_id":"s1"}`, claude()},
		{"claude empty event", "claude", `{"session_id":"s1","hook_event_name":""}`, claude()},
		{"claude non-string event", "claude", `{"session_id":"s1","hook_event_name":1,"source":"startup"}`, claude()},
		{"claude other event drops source", "claude", `{"session_id":"s1","hook_event_name":"UserPromptSubmit","source":"startup"}`, claude()},
		{"claude SubagentStop", "claude", `{"session_id":"s1","hook_event_name":"SubagentStop"}`, nil},
		{"claude subagent", "claude", `{"session_id":"s1","agent_id":"a1"}`, nil},
		{"claude empty agent_id", "claude", `{"session_id":"s1","agent_id":""}`, claude()},
		{"claude non-string agent_id", "claude", `{"session_id":"s1","agent_id":1}`, claude()},
		{"claude empty transcript", "claude", `{"session_id":"s1","transcript_path":""}`, claude()},
		{"claude non-string transcript", "claude", `{"session_id":"s1","transcript_path":1}`, claude()},
		{"claude empty source", "claude", `{"session_id":"s1","hook_event_name":"SessionStart","source":""}`, claude()},
		{"claude non-string source", "claude", `{"session_id":"s1","hook_event_name":"SessionStart","source":true}`, claude()},

		{"codex SessionStart sends no path", "codex", `{"session_id":"s1","hook_event_name":"SessionStart","transcript_path":"/r.jsonl","source":"resume"}`,
			codex("--session-start-source", "resume")},
		{"codex no event", "codex", `{"session_id":"s1","transcript_path":"/r.jsonl"}`, codex()},
		{"codex non-string event", "codex", `{"session_id":"s1","hook_event_name":1,"transcript_path":"/r.jsonl"}`, codex()},
		{"codex other event", "codex", `{"session_id":"s1","hook_event_name":"UserPromptSubmit","transcript_path":"/r.jsonl"}`, nil},
		{"codex SubagentStop", "codex", `{"session_id":"s1","hook_event_name":"SubagentStop","transcript_path":"/r.jsonl"}`, nil},
		{"codex agent_id is not checked", "codex", `{"session_id":"s1","agent_id":"a1","transcript_path":"/r.jsonl"}`, codex()},
		{"codex ephemeral null transcript", "codex", `{"session_id":"s1","transcript_path":null}`, nil},
		{"codex missing transcript", "codex", `{"session_id":"s1"}`, nil},
		{"codex empty transcript", "codex", `{"session_id":"s1","transcript_path":""}`, nil},

		{"missing session_id", "claude", `{}`, nil},
		{"empty session_id", "claude", `{"session_id":""}`, nil},
		{"null session_id", "claude", `{"session_id":null}`, nil},
		{"numeric session_id", "claude", `{"session_id":1}`, nil},
		{"whitespace session_id is not trimmed", "claude", `{"session_id":" "}`, base("claude", " ")},
		{"session_id with quotes and newline", "claude", `{"session_id":"a \"b\"\nc"}`, base("claude", "a \"b\"\nc")},
		{"keys are case-sensitive", "claude", `{"Session_Id":"s1","SESSION_ID":"s1"}`, nil},
		{"duplicate key keeps the last value", "claude", `{"session_id":"s0","session_id":"s1"}`, claude()},

		{"empty input", "claude", ``, nil},
		{"invalid JSON", "claude", `{"session_id":`, nil},
		{"concatenated JSON", "claude", `{"session_id":"s1"}{"session_id":"s2"}`, nil},
		{"top-level array", "claude", `[{"session_id":"s1"}]`, nil},
		{"top-level null", "claude", `null`, nil},
		{"top-level string", "claude", `"s1"`, nil},
		{"top-level number", "claude", `1`, nil},
		{"leading BOM", "claude", "\uFEFF" + `{"session_id":"s1"}`, nil},
		{"unknown agent", "gemini", `{"session_id":"s1"}`, nil},
	}
	for _, c := range cases {
		got := reportArgs(c.agent, "p1", []byte(c.input), 42)
		if !slices.Equal(got, c.want) {
			t.Errorf("%s:\n got %q\nwant %q", c.name, got, c.want)
		}
	}
}

// fixture は模擬 herdr を呼ぶための環境を整え、記録の置き場を返す。
func fixture(t *testing.T, behavior string) (dir, socket string) {
	t.Helper()
	self, err := filepath.Abs(os.Args[0])
	if err != nil {
		t.Fatal(err)
	}
	dir = t.TempDir()
	socket = filepath.Join(dir, mockSocketPrefix+behavior)
	t.Setenv("HERDR_ENV", "1")
	t.Setenv("HERDR_PANE_ID", "p1")
	t.Setenv("HERDR_SOCKET_PATH", socket)
	t.Setenv("HERDR_BIN_PATH", self)
	return dir, socket
}

func readRecord(t *testing.T, dir string) (record, bool) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, "record.json"))
	if errors.Is(err, os.ErrNotExist) {
		return record{}, false
	}
	if err != nil {
		t.Fatal(err)
	}
	var r record
	if err := json.Unmarshal(data, &r); err != nil {
		t.Fatal(err)
	}
	return r, true
}

const claudePayload = `{"session_id":"s 1","hook_event_name":"SessionStart","transcript_path":"/t \"x\".jsonl","source":"startup"}`

func TestRunReports(t *testing.T) {
	dir, socket := fixture(t, "ok")
	before := time.Now().UnixNano()
	run([]string{"session", "claude"}, strings.NewReader(claudePayload))
	after := time.Now().UnixNano()

	r, ok := readRecord(t, dir)
	if !ok {
		t.Fatal("herdr was not called")
	}
	if len(r.Args) < 9 || r.Args[7] != "--seq" {
		t.Fatalf("unexpected args %q", r.Args)
	}
	seq, err := strconv.ParseInt(r.Args[8], 10, 64)
	if err != nil || seq < before || seq > after {
		t.Errorf("seq %q is not epoch nanoseconds within [%d, %d]", r.Args[8], before, after)
	}
	want := slices.Concat(base("claude", "s 1"), []string{"--agent-session-path", "/t \"x\".jsonl", "--session-start-source", "startup"})
	want[8] = r.Args[8]
	if !slices.Equal(r.Args, want) {
		t.Errorf("args:\n got %q\nwant %q", r.Args, want)
	}
	if wantEnv := []string{"HERDR_SOCKET_PATH=" + socket}; !slices.Equal(r.Env, wantEnv) {
		t.Errorf("env: got %q, want %q", r.Env, wantEnv)
	}
}

func TestRunSkips(t *testing.T) {
	cases := []struct {
		name  string
		args  []string
		setup func(t *testing.T, dir string)
	}{
		{"wrong action", []string{"start", "claude"}, nil},
		{"missing agent", []string{"session"}, nil},
		{"unknown agent", []string{"session", "gemini"}, nil},
		{"outside Herdr", []string{"session", "claude"}, func(t *testing.T, _ string) { t.Setenv("HERDR_ENV", "0") }},
		{"no pane", []string{"session", "claude"}, func(t *testing.T, _ string) { t.Setenv("HERDR_PANE_ID", "") }},
		{"no socket", []string{"session", "claude"}, func(t *testing.T, _ string) { t.Setenv("HERDR_SOCKET_PATH", "") }},
		{"HERDR_BIN_PATH does not fall back to PATH", []string{"session", "claude"}, func(t *testing.T, dir string) {
			linkHerdr(t, dir)
			t.Setenv("HERDR_BIN_PATH", filepath.Join(dir, "missing"))
		}},
		{"relative PATH entry", []string{"session", "claude"}, func(t *testing.T, dir string) {
			linkHerdr(t, dir)
			t.Chdir(filepath.Join(dir, "bin"))
			t.Setenv("PATH", ".")
			t.Setenv("HERDR_BIN_PATH", "")
		}},
		{"non-executable herdr", []string{"session", "claude"}, func(t *testing.T, dir string) {
			path := filepath.Join(dir, "herdr")
			if err := os.WriteFile(path, nil, 0o644); err != nil {
				t.Fatal(err)
			}
			t.Setenv("HERDR_BIN_PATH", path)
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir, _ := fixture(t, "ok")
			if c.setup != nil {
				c.setup(t, dir)
			}
			run(c.args, strings.NewReader(claudePayload))
			if r, ok := readRecord(t, dir); ok {
				t.Errorf("herdr was called with %q", r.Args)
			}
		})
	}
}

// linkHerdr は dir/bin/herdr を模擬 herdr へのリンクにし、PATH をそこだけにする。
func linkHerdr(t *testing.T, dir string) {
	t.Helper()
	bin := filepath.Join(dir, "bin")
	if err := os.Mkdir(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(os.Getenv("HERDR_BIN_PATH"), filepath.Join(bin, "herdr")); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
}

func TestRunResolvesHerdrFromPath(t *testing.T) {
	dir, _ := fixture(t, "ok")
	linkHerdr(t, dir)
	t.Setenv("HERDR_BIN_PATH", "")
	run([]string{"session", "claude"}, strings.NewReader(claudePayload))
	if _, ok := readRecord(t, dir); !ok {
		t.Error("herdr on PATH was not called")
	}
}

// フック本体をこのテストバイナリの子プロセスとして起動し、herdr の結果に関係なく
// 何も出力せず exit 0 で終わることを見る。
func TestHookIsSilent(t *testing.T) {
	cases := []struct {
		behavior string
		binPath  func(dir string) string
	}{
		{"ok", nil},
		{"fail", nil},
		{"hang", nil},
		{"exec-failure", func(dir string) string {
			path := filepath.Join(dir, "not-a-program")
			_ = os.WriteFile(path, []byte("\x00\x01"), 0o755)
			return path
		}},
	}
	for _, c := range cases {
		t.Run(c.behavior, func(t *testing.T) {
			dir, _ := fixture(t, c.behavior)
			if c.binPath != nil {
				t.Setenv("HERDR_BIN_PATH", c.binPath(dir))
			}
			cmd := exec.Command(os.Args[0])
			cmd.Env = append(os.Environ(), runHookEnv+"=claude")
			cmd.Stdin = strings.NewReader(claudePayload)
			var out bytes.Buffer
			cmd.Stdout, cmd.Stderr = &out, &out
			start := time.Now()
			err := cmd.Run()
			elapsed := time.Since(start)
			if err != nil {
				t.Errorf("want exit 0, got %v", err)
			}
			if out.Len() != 0 {
				t.Errorf("want no output, got %q", out.String())
			}
			// 模擬 herdr は SIGTERM を無視して 10 秒眠るので、この上限内に返れば
			// SIGKILL で終了・回収されている。
			if elapsed > 5*time.Second {
				t.Errorf("hook took %v", elapsed)
			}
			if _, called := readRecord(t, dir); called != (c.binPath == nil) {
				t.Errorf("herdr called = %v", called)
			}
		})
	}
}
