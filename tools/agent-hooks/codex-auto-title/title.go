package main

import (
	"regexp"
	"strings"

	"github.com/clipperhouse/uax29/v2/graphemes"
)

const maxTitleGraphemes = 40

// JavaScript の \s と String.prototype.trim が空白とみなす文字。Go の \s は ASCII の
// 空白しか含まず、全角スペースの後ろまで URL として消してしまうので明示する。
const jsSpace = `\t\n\v\f\r \x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}\x{feff}`

var (
	codeFence     = regexp.MustCompile("(?s)```.*?```")
	urlToken      = regexp.MustCompile(`https?://[^` + jsSpace + `]+`)
	control       = regexp.MustCompile(`[\p{Cc}\p{Cf}]+`)
	spaces        = regexp.MustCompile(`[` + jsSpace + `]+`)
	trailing      = regexp.MustCompile(`[。．.!！?？,:：;；、` + jsSpace + `]+$`)
	edgeSpaces    = regexp.MustCompile(`^[` + jsSpace + `]+|[` + jsSpace + `]+$`)
	issueInBranch = regexp.MustCompile(`(?:^|[/_-])#?(\d{1,7})(?:$|[/_-])`)
)

func jsTrim(s string) string {
	return edgeSpaces.ReplaceAllString(s, "")
}

func graphemeCount(s string) int {
	n := 0
	for g := graphemes.FromString(s); g.Next(); {
		n++
	}
	return n
}

func truncate(s string, maximum int) string {
	if graphemeCount(s) <= maximum {
		return s
	}
	if maximum <= 1 {
		return "…"
	}
	var b strings.Builder
	g := graphemes.FromString(s)
	for range maximum - 1 {
		g.Next()
		b.WriteString(g.Value())
	}
	return b.String() + "…"
}

func fallbackName(cwd any) string {
	path, ok := cwd.(string)
	if !ok {
		return "Codex session"
	}
	path = strings.TrimRight(path, `\/`)
	if name := path[strings.LastIndexAny(path, `\/`)+1:]; name != "" {
		return name
	}
	return "Codex session"
}

func branchIssue(branch any) string {
	s, _ := branch.(string)
	if m := issueInBranch.FindStringSubmatch(s); m != nil {
		return m[1]
	}
	return ""
}

func makeTitle(messages, cwd, branch any) string {
	var parts []string
	if items, ok := messages.([]any); ok {
		for _, item := range items {
			if s, ok := item.(string); ok {
				parts = append(parts, s)
			}
		}
	}
	prompt := strings.Join(parts, " ")
	prompt = codeFence.ReplaceAllString(prompt, " ")
	prompt = urlToken.ReplaceAllString(prompt, " ")
	prompt = control.ReplaceAllString(prompt, " ")
	prompt = jsTrim(spaces.ReplaceAllString(prompt, " "))
	prompt = trailing.ReplaceAllString(prompt, "")

	prefix := ""
	if issue := branchIssue(branch); issue != "" {
		prefix = "#" + issue + " "
	}
	base := prompt
	if base == "" {
		base = fallbackName(cwd)
	}
	// prefix と本文は別々に数える。連結してから数えると、結合文字で始まる本文が
	// prefix 末尾の空白とまとまり、元の実装と結果が変わる。
	return prefix + truncate(base, maxTitleGraphemes-graphemeCount(prefix))
}
