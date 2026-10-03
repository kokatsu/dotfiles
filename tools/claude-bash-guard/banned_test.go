package main

// 判定を固定する。ケースは改行や U+0085 を含むため JSON で持つ。
// プロセスとしての振る舞い (fail-closed、シグナル、出力の失敗) は
// scripts/test-banned-commands.sh が見る。

import (
	"bytes"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"mvdan.cc/sh/v3/syntax"
	"mvdan.cc/sh/v3/syntax/typedjson"

	"claude-bash-guard/rules"
)

type bannedCase struct {
	Want    string `json:"want"`
	Command string `json:"command"`
	Label   string `json:"label"`
}

func loadCases(t *testing.T) []bannedCase {
	t.Helper()
	data, err := os.ReadFile("testdata/banned-cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []bannedCase
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	return cases
}

func loadRules(t *testing.T) []rules.Rule {
	t.Helper()
	ruleSet, err := rules.Load()
	if err != nil {
		t.Fatal(err)
	}
	return ruleSet
}

func TestBannedCases(t *testing.T) {
	ruleSet := loadRules(t)
	for _, c := range loadCases(t) {
		name := c.Label
		if name == "" {
			name = c.Command
		}
		t.Run(c.Want+": "+name, func(t *testing.T) {
			message := checkBanned(c.Command, ruleSet)
			switch {
			case c.Want == "block" && message == "":
				t.Error("should be blocked, but was allowed")
			case c.Want == "allow" && message != "":
				t.Errorf("should be allowed, but was blocked: %s", message)
			}
		})
	}
}

// フックは触れた判定のうち先頭だけを使う。1 行 = 判定コード<TAB>コマンド。
func TestVerdictPrecedence(t *testing.T) {
	ruleSet := loadRules(t)
	data, err := os.ReadFile("testdata/verdict-precedence-cases.txt")
	if err != nil {
		t.Fatal(err)
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		want, command, _ := strings.Cut(line, "\t")
		t.Run(want+": "+command, func(t *testing.T) {
			message, ok := verdictMessages[verdict(want)]
			if !ok {
				t.Fatalf("unknown verdict %s", want)
			}
			if got := checkBanned(command, ruleSet); got != message {
				t.Errorf("expected verdict %s, got: %s", want, got)
			}
		})
	}
}

// syntax.Walk が辿らない欄に CallExpr があると、そのコマンドは検査されずに通る。
// typedjson は構造体の全欄を reflect で書き出すので、その中の CallExpr の数と
// 突き合わせて、Walk が取りこぼしていないことを確かめる。
func TestWalkReachesEveryCallExpr(t *testing.T) {
	for _, c := range loadCases(t) {
		file, err := parse(c.Command)
		if err != nil {
			continue
		}
		walked := 0
		syntax.Walk(file, func(node syntax.Node) bool {
			if _, ok := node.(*syntax.CallExpr); ok {
				walked++
			}
			return true
		})
		var encoded bytes.Buffer
		if err := typedjson.Encode(&encoded, file); err != nil {
			t.Fatal(err)
		}
		if want := strings.Count(encoded.String(), `"Type":"CallExpr"`); walked != want {
			t.Errorf("Walk reached %d CallExpr, the AST has %d: %q", walked, want, c.Command)
		}
	}
}

func TestReadCommand(t *testing.T) {
	cases := []struct {
		payload string
		present bool
		fails   bool
	}{
		{`{"tool_input":{"command":"ls"}}`, true, false},
		{`{"tool_input":{}}`, false, false},
		{`{"tool_input":null}`, false, false},
		{`{"tool_input":{"command":null}}`, false, false},
		{`{"tool_input":{"command":42}}`, false, true},
		{`{`, false, true},
		{``, false, true},
		{"{\"tool_input\":{\"command\":\"echo ok\"}}\x00x", false, true},
	}
	for _, c := range cases {
		_, present, err := readCommand(strings.NewReader(c.payload))
		if present != c.present || (err != nil) != c.fails {
			t.Errorf("%q: present=%v err=%v", c.payload, present, err)
		}
	}
}

func TestParseFollowsShebang(t *testing.T) {
	// 配列の代入は bash では解析できるが POSIX sh では構文エラーになる。
	if _, err := parse("a=(1 2)"); err != nil {
		t.Errorf("bash by default: %v", err)
	}
	if _, err := parse("#!/bin/sh\na=(1 2)"); err == nil {
		t.Error("a sh shebang should select the POSIX dialect")
	}
}

func TestHerdrInput(t *testing.T) {
	blocked := []string{
		"herdr agent prompt w1:p1 test",
		"exec herdr agent prompt w1:p1 test",
		"if true; then herdr agent prompt w1:p1 test; fi",
		"/usr/bin/env herdr agent prompt w1:p1 test",
		"exec /usr/bin/env -i FOO=bar herdr pane send-text w1:p1 test",
		"case x in x) herdr agent send-keys w1:p1 test ;; esac",
		"while herdr pane run w1:p1 test; do true; done",
		"true\nherdr pane send-keys w1:p1 test",
	}
	allowed := []string{
		"herdr agent list",
		"herdr agent read w1:p1",
		`herdr-peer prompt "review the diff"`,
		`git commit -m "mention herdr agent prompt in documentation"`,
		`printf '%s\n' 'herdr pane send-text w1:p1 test'`,
	}
	for _, command := range blocked {
		if verdicts, _ := commandVerdicts(command); !herdrInputCommand(command, verdicts) {
			t.Errorf("should be blocked: %q", command)
		}
	}
	for _, command := range allowed {
		if verdicts, _ := commandVerdicts(command); herdrInputCommand(command, verdicts) {
			t.Errorf("should be allowed: %q", command)
		}
	}
}
