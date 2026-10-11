package main

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// testdata/titles.json の title は、Deno で動いていた元の実装 (scripts/codex-auto-title.ts)
// が同じ入力から作った値。
func TestMakeTitleMatchesDenoOutputs(t *testing.T) {
	data, err := os.ReadFile("testdata/titles.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []map[string]any
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		if got := makeTitle(c["messages"], c["cwd"], c["branch"]); got != c["title"] {
			t.Errorf("makeTitle(%q, %q, %q) = %q, want %q", c["messages"], c["cwd"], c["branch"], got, c["title"])
		}
	}
}

func TestMakeTitle(t *testing.T) {
	cases := []struct {
		name                  string
		messages, cwd, branch any
		want                  string
	}{
		{
			"normalizes a prompt and prefixes a branch issue",
			[]any{"  Codex のセッション名を   自動設定してください。 https://example.com/x "}, "/work/dotfiles", "feature/123-auto-title",
			"#123 Codex のセッション名を 自動設定してください",
		},
		{"uses the working directory for an empty prompt", []any{"https://example.com"}, "/work/dotfiles/", nil, "dotfiles"},
		{"truncates titles by grapheme", []any{strings.Repeat("あ", 45)}, "/work/dotfiles", nil, strings.Repeat("あ", 39) + "…"},
		{"does not treat a date branch as an issue", []any{"セッション名"}, "/work/dotfiles", "20260909", "セッション名"},
		{"ends a URL at an ideographic space", []any{"see https://example.com　次の文"}, nil, nil, "see 次の文"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := makeTitle(c.messages, c.cwd, c.branch); got != c.want {
				t.Errorf("got %q, want %q", got, c.want)
			}
		})
	}
}
