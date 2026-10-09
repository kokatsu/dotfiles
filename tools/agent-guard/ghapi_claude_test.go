package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"strings"
	"testing"
)

type ghAPICase struct {
	id, decision, reason, command string
}

func loadGhAPICases(t *testing.T) []ghAPICase {
	t.Helper()
	data, err := os.ReadFile("testdata/gh-api-guard-cases.tsv")
	if err != nil {
		t.Fatal(err)
	}
	var cases []ghAPICase
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.SplitN(line, "\t", 4)
		if len(fields) != 4 {
			t.Fatalf("malformed case: %q", line)
		}
		cases = append(cases, ghAPICase{fields[0], fields[1], fields[2], fields[3]})
	}
	return append(cases,
		// 改行を含む形は表に書けない。
		ghAPICase{"I1", "allow", ghAPIAllowReason, "gh ap\\\ni repos/o/r -X GET"},
		ghAPICase{"I2", "allow", ghAPIAllowReason, "gh a\\\np\\\ni repos/o/r -X GET"},
	)
}

func TestCheckGhAPI(t *testing.T) {
	for _, c := range loadGhAPICases(t) {
		got, ok := checkGhAPI(c.command)
		switch {
		case c.decision == "none":
			if ok {
				t.Errorf("%s %q: want no decision, got %s / %s", c.id, c.command, got.decision, got.reason)
			}
		case !ok:
			t.Errorf("%s %q: want %s, got no decision", c.id, c.command, c.decision)
		case got.decision != c.decision || !strings.Contains(got.reason, c.reason):
			t.Errorf("%s %q: want %s / *%s*, got %s / %s", c.id, c.command, c.decision, c.reason, got.decision, got.reason)
		}
	}
}

type failingReader struct{ t *testing.T }

func (r failingReader) Read([]byte) (int, error) {
	r.t.Fatal("read stdin although it is a terminal")
	return 0, nil
}

func TestRunGhAPI(t *testing.T) {
	cases := []struct {
		name, payload, want string // want は判定。"" なら出力なし
	}{
		{"allow", `{"tool_input":{"command":"gh api r -X GET"}}`, "allow"},
		{"deny", `{"tool_input":{"command":"gh api r"}}`, "deny"},
		{"unrelated", `{"tool_input":{"command":"echo hello"}}`, ""},
		{"empty", ``, "ask"},
		{"malformed", `{`, "ask"},
		{"trailing", `{"tool_input":{"command":"gh api r -X GET"}} {}`, "ask"},
		{"missing command", `{"tool_input":{}}`, "ask"},
		{"null command", `{"tool_input":{"command":null}}`, "ask"},
		{"non-string command", `{"tool_input":{"command":1}}`, "ask"},
	}
	for _, c := range cases {
		var out bytes.Buffer
		runGhAPI(strings.NewReader(c.payload), false, &out)
		if c.want == "" {
			if out.Len() != 0 {
				t.Errorf("%s: want no output, got %q", c.name, out.String())
			}
			continue
		}
		var got struct {
			HookSpecificOutput struct {
				HookEventName      string `json:"hookEventName"`
				PermissionDecision string `json:"permissionDecision"`
			} `json:"hookSpecificOutput"`
		}
		if !strings.HasSuffix(out.String(), "}\n") || strings.Count(out.String(), "\n") != 1 {
			t.Errorf("%s: want one JSON line, got %q", c.name, out.String())
		}
		if err := json.Unmarshal(out.Bytes(), &got); err != nil {
			t.Errorf("%s: %v in %q", c.name, err, out.String())
			continue
		}
		if got.HookSpecificOutput.HookEventName != "PreToolUse" || got.HookSpecificOutput.PermissionDecision != c.want {
			t.Errorf("%s: want %s, got %q", c.name, c.want, out.String())
		}
	}

	var out bytes.Buffer
	runGhAPI(failingReader{t}, true, &out)
	if out.Len() != 0 {
		t.Errorf("terminal: want no output, got %q", out.String())
	}
}

// guard の panic 経路は os.Exit で終わるので、このテストバイナリを子プロセスとして
// 起動し、終了コードと出力を見る。
func TestGuardPanic(t *testing.T) {
	if mode := os.Getenv("AGENT_GUARD_PANIC_MODE"); mode != "" {
		guard(mode, func() { panic("boom") })
		return
	}
	for mode, wantCode := range map[string]int{"gh-api": 0, "banned": 2} {
		cmd := exec.Command(os.Args[0], "-test.run=^TestGuardPanic$")
		cmd.Env = append(os.Environ(), "AGENT_GUARD_PANIC_MODE="+mode)
		var stdout, stderr bytes.Buffer
		cmd.Stdout, cmd.Stderr = &stdout, &stderr
		err := cmd.Run()
		code := 0
		if exitErr, ok := err.(*exec.ExitError); ok {
			code = exitErr.ExitCode()
		} else if err != nil {
			t.Fatal(err)
		}
		if code != wantCode {
			t.Errorf("%s: want exit %d, got %d (stderr %q)", mode, wantCode, code, stderr.String())
		}
		if strings.Contains(stdout.String(), "permissionDecision") {
			t.Errorf("%s: want no decision, got %q", mode, stdout.String())
		}
	}
}
