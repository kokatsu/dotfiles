package main

// GH_API_METHOD: gh api の呼び出しに、値の読める HTTP メソッドの明示を求める。
// codex モードだけの判定で、Claude Code には gh-api モード (ghapi_claude.go)
// があるので banned モードでは飛ばす。
//
// 呼び出しはコマンド位置や wrapper を読まず、字面の gh と api (または読めない
// 語) が並んだ所とみなす。一覧にない wrapper が前に付いても見落とさない代わりに、
// `echo gh api r` も拒否する。
//
// 値を取るオプションの表は gh-api モードと共有する。

import (
	"regexp"
	"slices"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

const ghAPIShortValue = "FHXqpft"

var ghAPILongValue = map[string]bool{
	"cache": true, "field": true, "header": true, "hostname": true, "input": true,
	"jq": true, "method": true, "preview": true, "raw-field": true, "template": true,
}

// 語の文字列 (wordText) だけでは分からない、展開についての情報。
type wordInfo struct {
	literal    bool   // 展開を含まない
	splittable bool   // 語分割で別の語を増やしうる
	prefix     string // 最初の展開より前の字面 (wordText と同じ読み方)
	// env -S が展開を含む文字列を分割して作った語。字面として並べて呼び出しを
	// 見つけるが、値は信用しない。
	unsure bool
}

func readWordInfo(word *syntax.Word) wordInfo {
	info := wordInfo{literal: true}
	known := true
	add := func(text string) {
		if known {
			info.prefix += text
		}
	}
	unknown := func() {
		info.literal = false
		known = false
	}
	for _, part := range word.Parts {
		switch part := part.(type) {
		case *syntax.Lit:
			// 引用の外の glob とブレース展開は、ファイル名や複数の語に置き換わる。
			if at := expansionAt(part.Value); at >= 0 {
				add(strings.ReplaceAll(part.Value[:at], `\`, ""))
				info.splittable = true
				unknown()
				continue
			}
			add(strings.ReplaceAll(part.Value, `\`, ""))
		case *syntax.SglQuoted:
			if part.Dollar {
				unknown()
			} else {
				add(part.Value)
			}
		case *syntax.DblQuoted:
			for _, inner := range part.Parts {
				switch inner := inner.(type) {
				case *syntax.Lit:
					add(inner.Value)
				case *syntax.ParamExp:
					// "$@" と添字つきは引用の中でも複数語に増える。
					if inner.Param != nil && (inner.Param.Value == "@" || inner.Param.Value == "*") || inner.Index != nil {
						info.splittable = true
					}
					unknown()
				default:
					info.splittable = true
					unknown()
				}
			}
		default:
			info.splittable = true
			unknown()
		}
	}
	return info
}

var braceExpansion = regexp.MustCompile(`^\{[^{}]*(,|\.\.)[^{}]*\}`)

// 引用の外の Lit の値で、エスケープされていない glob の文字 (* ? [) か
// ブレース展開が始まる位置。無ければ -1。
func expansionAt(raw string) int {
	for i := 0; i < len(raw); i++ {
		switch raw[i] {
		case '\\':
			i++
		case '*', '?', '[':
			return i
		case '{':
			if braceExpansion.MatchString(raw[i:]) {
				return i
			}
		}
	}
	return -1
}

func readWordInfos(words []*syntax.Word) []wordInfo {
	infos := make([]wordInfo, len(words))
	for i, word := range words {
		infos[i] = readWordInfo(word)
	}
	return infos
}

// alignScripts と同じく、ラッパーを剥がした後の引数を元の語の末尾と揃えて
// 情報を引き継ぐ。stripWrappers は先頭を commandName で書き換えるので、その語は
// commandName を通して比べる。env -S の分割で作られた語は元の語と一致しない。
// それらは字面として扱い、元の語に展開があるか、自身が $ を含むなら unsure にする。
// env -S は自分でも ${VAR} を展開するため。
func alignInfos(words []string, infos []wordInfo, rest []string) []wordInfo {
	allLiteral := true
	for _, info := range infos {
		allLiteral = allLiteral && info.literal
	}
	out := make([]wordInfo, len(rest))
	for i, arg := range rest {
		if k := len(words) - len(rest) + i; k >= 0 && (words[k] == arg || commandName(words[k]) == arg) {
			out[i] = infos[k]
			continue
		}
		out[i] = wordInfo{
			literal: true,
			prefix:  arg,
			unsure:  !allLiteral || strings.Contains(arg, "$"),
		}
	}
	return out
}

// 展開を含む語が、-- より前でオプションとしてメソッドを持ち込めないなら true。
func optionSafe(info wordInfo) bool {
	switch {
	case info.splittable || info.prefix == "":
		return false
	case !strings.HasPrefix(info.prefix, "-"):
		return true
	case strings.HasPrefix(info.prefix, "--"):
		// 名前まで読めていて、メソッド以外の値を取るなら、展開はその値にしかならない。
		name, _, named := strings.Cut(info.prefix[2:], "=")
		return named && name != "method" && ghAPILongValue[name]
	}
	for _, c := range info.prefix[1:] {
		switch {
		case c == 'X':
			return false
		case strings.ContainsRune(ghAPIShortValue, c):
			return true
		}
	}
	// 真偽値の文字だけで字面が尽きた。展開が X を足せる。
	return false
}

func methodReadable(text string, info wordInfo) bool {
	return info.literal && text != ""
}

// gh api の後ろの語に、読めるメソッド指定が 1 つ以上あり、読めないメソッド指定が
// 無ければ true。
func explicitMethod(texts []string, infos []wordInfo) bool {
	seen := false
	// 値を取るオプションが次の語を飲み込む。その語が語分割を起こすなら、値の後ろに
	// オプションを残せる。
	eats := func(i int) bool { return i+1 >= len(texts) || !infos[i+1].splittable }
	for i := 0; i < len(texts); i++ {
		text, info := texts[i], infos[i]
		if !info.literal {
			if !optionSafe(info) {
				return false
			}
			continue
		}
		if text == "--" {
			break
		}
		if !strings.HasPrefix(text, "-") || text == "-" {
			continue
		}

		if strings.HasPrefix(text, "--") {
			name, value, glued := strings.Cut(text[2:], "=")
			switch {
			case name == "method" && glued:
				if value == "" {
					return false
				}
				seen = true
			case name == "method":
				if i+1 >= len(texts) || !methodReadable(texts[i+1], infos[i+1]) {
					return false
				}
				seen = true
				i++
			case ghAPILongValue[name] && !glued:
				if !eats(i) {
					return false
				}
				i++
			}
			continue
		}

		cluster := text[1:]
		for j := 0; j < len(cluster); j++ {
			c := cluster[j]
			if !strings.ContainsRune(ghAPIShortValue, rune(c)) {
				continue
			}
			if j+1 < len(cluster) {
				seen = seen || c == 'X'
				break
			}
			if c == 'X' {
				if i+1 >= len(texts) || !methodReadable(texts[i+1], infos[i+1]) {
					return false
				}
				seen = true
			} else if !eats(i) {
				return false
			}
			i++
			break
		}
	}
	return seen
}

// 字面の gh と、字面の api または読めない語が並んだ所を呼び出しの開始とする。
// 各呼び出しは次の呼び出しの手前まで。後ろの呼び出しの -X GET を借りないため。
func ghAPIMissingMethod(texts []string, infos []wordInfo) bool {
	var starts []int
	for i := 0; i+1 < len(texts); i++ {
		if infos[i].literal && commandName(texts[i]) == "gh" &&
			(!infos[i+1].literal || texts[i+1] == "api") {
			starts = append(starts, i)
		}
	}
	for k, start := range starts {
		end := len(texts)
		if k+1 < len(starts) {
			end = starts[k+1]
		}
		if slices.ContainsFunc(infos[start:end], func(info wordInfo) bool { return info.unsure }) ||
			!explicitMethod(texts[start+2:end], infos[start+2:end]) {
			return true
		}
	}
	return false
}
