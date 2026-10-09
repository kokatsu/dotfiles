package main

// gh-api モード: Claude Code の `gh api` が GET を明示した読み取りだと証明できた
// ときだけ allow を返す PreToolUse 判定。証明できなければ ask へ落とす。ただし
// メソッドの書き忘れだけは deny にする。ask の理由はユーザーにしか見えず、deny の
// 理由だけが Claude に届くので、deny なら Claude が -X GET を足して自分で再実行できる。
//
// 判定は生文字列ではなく AST の argv に対して行う。値の中身が旗に見えるだけの
// 読み取り (`--jq '… -X DELETE …'`) を ask にせず、展開が旗を持ち込める形
// (`gh api "$@"`) を allow にしないためである。
//
// settings.json の `if: "Bash(gh api *)"` が入口なので、この判定が走る時点で
// `gh api` があるか、Claude Code がコマンドを解析できなかったかのどちらかである。
// 後者では gh api の無い入力も届くため、判定を出さない経路を残す。
//
// codex モードの GH_API_METHOD (ghapi.go) とは別の判定で、GET 以外の読める
// メソッドを認めず、コマンド位置の gh だけを見る。wrapper も banned モードより
// 少ない種類しか剥がさない。剥がさない wrapper は間接呼び出しとして ask になり、
// 剥がす種類を増やすと allow が増える。

import (
	"regexp"
	"strings"
	"unicode/utf8"

	"mvdan.cc/sh/v3/syntax"

	"agent-guard/rules"
)

// gh api の短オプション。値を取る文字を取り違えると束の解釈が壊れる。真偽値を
// 値を取る側に入れると `-iF a=b` の F が i に食われて POST が素通りするので、
// `gh api --help` が値を取ると書いている文字だけを入れる。値を取る側の表は
// ghapi.go の ghAPIShortValue / ghAPILongValue を使う。
const (
	ghAPIShortBool = "i"
	ghAPIShortBody = "Ff"
)

var ghAPILongBool = map[string]bool{
	"allow-escape-sequences": true, "help": true, "include": true, "paginate": true,
	"silent": true, "slurp": true, "verbose": true,
}

var ghAPILongBody = map[string]bool{"field": true, "input": true, "raw-field": true}

const (
	ghAPIBodyReason       = "gh api: body-bearing flag (-f/-F/--field/--raw-field/--input) implies POST"
	ghAPINonLiteralReason = "gh api: an expanded argument could add a flag — confirm intent"
	ghAPIIndirectReason   = "gh api: indirect invocation (eval / sh -c / xargs) — confirm intent"
	ghAPIUnreadableReason = "gh api: an expanded word hides what runs — confirm intent"
	ghAPIUnparsedReason   = "gh api: could not parse this command as bash — confirm intent"
	ghAPINoMethodReason   = "gh api: no explicit HTTP method — re-run with -X GET for a read"
	ghAPIAllowReason      = "gh api: explicit GET"
)

// 移植元の TypeScript の \s は ECMAScript の空白集合に一致する。Go の \s は
// ASCII だけなので、同じ集合を明示する。
var (
	ghAPIText   = regexp.MustCompile(`\bgh[` + rules.SpaceClass + `]+api\b`)
	apiWordText = regexp.MustCompile(`\bapi\b`)
)

type ghAPIDecision struct {
	decision string // allow / ask / deny
	reason   string
}

func ghAPIMethodReason(verb *string) string {
	v := "?"
	if verb != nil {
		v = *verb
	}
	return "gh api: HTTP method override to '" + v + "' (not GET) — confirm intent"
}

// 語分割を起こす部分。引用の外の展開はすべて、引用の中でも "$@" と添字つきは
// 複数語に増える。`"repos/${a[@]}"` は字面で始まっても 2 語目に旗を置ける。
func ghAPISplitsWords(part syntax.WordPart) bool {
	switch part := part.(type) {
	case *syntax.Lit, *syntax.SglQuoted:
		return false
	case *syntax.DblQuoted:
		for _, inner := range part.Parts {
			exp, ok := inner.(*syntax.ParamExp)
			if !ok {
				if ghAPISplitsWords(inner) {
					return true
				}
				continue
			}
			if exp.Param != nil && (exp.Param.Value == "@" || exp.Param.Value == "*") || exp.Index != nil {
				return true
			}
		}
		return false
	}
	return true
}

// 展開せずに読める先頭の字面と、その部分が最後まで読めたか。バックスラッシュは
// 落とさない。`-X\ GET` の実引数は `-X GET` だが、ここでは `-X\ GET` のまま GET と
// 一致せず ask になる。落とすと `-\X DELETE` が旗として読めてしまう。
// wordText と readWordInfo はバックスラッシュを落とすので、ここでは使えない。
func ghAPILiteralPrefix(part syntax.WordPart) (string, bool) {
	switch part := part.(type) {
	case *syntax.Lit:
		return part.Value, true
	case *syntax.SglQuoted:
		// $'…' は ANSI-C エスケープを解かないと中身が分からない。解かないので不明。
		if part.Dollar {
			return "", false
		}
		return part.Value, true
	case *syntax.DblQuoted:
		var text strings.Builder
		for _, inner := range part.Parts {
			read, complete := ghAPILiteralPrefix(inner)
			text.WriteString(read)
			if !complete {
				return text.String(), false
			}
		}
		return text.String(), true
	}
	return "", false
}

type ghAPIWord struct {
	literal    *string // 全体が字面なら展開後の文字列、展開を含むなら nil
	prefix     string  // 最初の展開より前の字面。展開で始まる語では空文字
	splittable bool
}

func readGhAPIWord(word *syntax.Word) ghAPIWord {
	literal := ""
	out := ghAPIWord{literal: &literal}
	known := true
	for _, part := range word.Parts {
		if ghAPISplitsWords(part) {
			out.splittable = true
		}
		text, complete := ghAPILiteralPrefix(part)
		if known {
			out.prefix += text
		}
		if !complete {
			out.literal = nil
			known = false
		} else if out.literal != nil {
			literal += text
		}
	}
	return out
}

func isGet(verb *string) bool {
	return verb != nil && strings.EqualFold(*verb, "get")
}

type ghAPICluster struct {
	reason     string // "" なら問題なし
	eatsNext   bool
	valueTaken bool
	sawGet     bool
}

// 束ねられた短オプションを左から解く。値を取る文字が現れたら束の残りが値になり、
// 残りが空なら次の語を食う。
func ghAPIShortCluster(cluster string, next *ghAPIWord) ghAPICluster {
	for i, letter := range cluster {
		if strings.ContainsRune(ghAPIShortBool, letter) {
			continue
		}
		if !strings.ContainsRune(ghAPIShortValue, letter) {
			return ghAPICluster{reason: "gh api: unknown flag '-" + string(letter) + "' — confirm intent"}
		}
		if strings.ContainsRune(ghAPIShortBody, letter) {
			return ghAPICluster{reason: ghAPIBodyReason, valueTaken: true}
		}
		glued := cluster[i+utf8.RuneLen(letter):]
		if letter != 'X' {
			return ghAPICluster{eatsNext: glued == "", valueTaken: true}
		}
		verb := &glued
		if glued == "" {
			verb = nil
			if next != nil {
				verb = next.literal
			}
		}
		result := ghAPICluster{eatsNext: glued == "", valueTaken: true, sawGet: isGet(verb)}
		if !result.sawGet {
			result.reason = ghAPIMethodReason(verb)
		}
		return result
	}
	return ghAPICluster{}
}

// 展開を含む語。語分割が起きず、字面で読めた頭が旗でなければオペランドであり、
// 展開しても旗にはならない。旗なら、読めた頭から旗を見分けて理由を具体化する。
// 値を取る旗まで読めていれば展開はその値にしかならないので、そこで安全になる。
func ghAPIExpansionReason(word ghAPIWord) string {
	if word.splittable || word.prefix == "" {
		return ghAPINonLiteralReason
	}
	if !strings.HasPrefix(word.prefix, "-") {
		return ""
	}
	if strings.HasPrefix(word.prefix, "--") {
		name, _, _ := strings.Cut(word.prefix[2:], "=")
		switch {
		case ghAPILongBody[name]:
			return ghAPIBodyReason
		case name == "method":
			return ghAPIMethodReason(nil)
		case ghAPILongValue[name] || ghAPILongBool[name]:
			return ""
		}
		return ghAPINonLiteralReason
	}
	cluster := ghAPIShortCluster(word.prefix[1:], nil)
	if cluster.reason != "" {
		return cluster.reason
	}
	// 真偽値の文字だけで字面が尽きた。展開が X や F を足せる。
	if !cluster.valueTaken {
		return ghAPINonLiteralReason
	}
	return ""
}

// gh api の後ろの argv を歩き、読み取りと証明できなければ理由を返す。
func ghAPIArgvReason(words []ghAPIWord) string {
	endOfOptions := false
	sawGet := false
	next := func(i int) *ghAPIWord {
		if i+1 < len(words) {
			return &words[i+1]
		}
		return nil
	}
	// 旗の値として次の語を飲み込むとき、その語が語分割を起こすなら飲み込めない。
	// `-H $H` は H="x -X DELETE" なら 3 語に増え、値の後ろに旗が残る。
	eats := func(i int) bool { return next(i) == nil || !next(i).splittable }
	nextLiteral := func(i int) *string {
		if n := next(i); n != nil {
			return n.literal
		}
		return nil
	}

	for i := 0; i < len(words); i++ {
		word := words[i]
		if word.literal == nil {
			if endOfOptions {
				continue
			}
			if reason := ghAPIExpansionReason(word); reason != "" {
				return reason
			}
			continue
		}

		text := *word.literal
		if endOfOptions || !strings.HasPrefix(text, "-") || text == "-" {
			continue
		}
		if text == "--" {
			endOfOptions = true
			continue
		}

		if strings.HasPrefix(text, "--") {
			name, value, hasValue := strings.Cut(text[2:], "=")
			if ghAPILongBody[name] {
				return ghAPIBodyReason
			}
			if !ghAPILongValue[name] && !ghAPILongBool[name] {
				return "gh api: unknown flag '--" + name + "' — confirm intent"
			}
			if name == "method" {
				verb := nextLiteral(i)
				if hasValue {
					verb = &value
				}
				if !isGet(verb) {
					return ghAPIMethodReason(verb)
				}
				sawGet = true
			}
			if ghAPILongValue[name] && !hasValue {
				if !eats(i) {
					return ghAPINonLiteralReason
				}
				i++
			}
			continue
		}

		cluster := ghAPIShortCluster(text[1:], next(i))
		if cluster.reason != "" {
			return cluster.reason
		}
		sawGet = sawGet || cluster.sawGet
		if cluster.eatsNext {
			if !eats(i) {
				return ghAPINonLiteralReason
			}
			i++
		}
	}

	if !sawGet {
		return ghAPINoMethodReason
	}
	return ""
}

// banned モードの unwrap より少ない wrapper だけを剥がす。コマンド名を
// commandName で正規化しないので、/usr/bin/gh や =gh は gh と読まない。
func ghAPIStripWrappers(args []string) []string {
	for len(args) > 0 {
		switch args[0] {
		case "command":
			args = stripCommandOpts(args[1:])
		case "env":
			args = stripEnvOpts(args[1:])
		case "sudo", "doas":
			args = stripSudoOpts(args[1:])
		case "exec":
			args = stripExecOpts(args[1:])
		case "builtin":
			args = args[1:]
			if len(args) > 0 && args[0] == "--" {
				args = args[1:]
			}
		default:
			return args
		}
	}
	return args
}

// gh api を自分の argv の外へ隠している呼び出し。中身を読めないので ask にする。
func hidesGhAPI(texts []string) bool {
	for i, text := range texts {
		if ghAPIText.MatchString(text) || text == "gh" && i+1 < len(texts) && texts[i+1] == "api" {
			return true
		}
	}
	return false
}

// jsSlice は JavaScript の Array.prototype.slice の位置の解釈で、負の値は末尾から
// 数える。env -S は語を分割して増やすので、剥がした後の語数が元より多くなり、
// 下の offset が負になる。移植元はその負の位置で argv を切っており、判定は
// testdata/gh-api-guard-cases.tsv の M 行が固定している。
func jsSlice(n, i int) int {
	if i < 0 {
		return max(n+i, 0)
	}
	return min(i, n)
}

func ghAPIDecide(file *syntax.File) (ghAPIDecision, bool) {
	seen := false
	mayBeAPI := false
	reason := ""
	setReason := func(r string) {
		if reason == "" {
			reason = r
		}
	}

	// 採用される理由は走査順の先頭なので、順序自体が仕様。deny と ask が入れ替わる
	// 形は testdata/gh-api-guard-cases.tsv の J 行が固定している。
	syntax.Walk(file, func(node syntax.Node) bool {
		call, ok := node.(*syntax.CallExpr)
		if !ok || len(call.Args) == 0 {
			return true
		}
		words := make([]ghAPIWord, len(call.Args))
		texts := make([]string, len(call.Args))
		for i, arg := range call.Args {
			words[i] = readGhAPIWord(arg)
			texts[i] = wordText(arg)
		}
		for i, text := range texts {
			if apiWordText.MatchString(text) ||
				words[i].literal != nil && *words[i].literal == "gh" && i+1 < len(words) && words[i+1].literal == nil {
				mayBeAPI = true
			}
		}
		stripped := ghAPIStripWrappers(texts)
		offset := len(texts) - len(stripped)

		// wordText は展開を空文字へ潰すので、剥がす語数も何のコマンドかも、読めない
		// 語をまたいだ時点で当てにならない。`env -u $V gh api r` は V が 2 語以上へ
		// 割れれば別のコマンドを走らせるし、`$CMD api r -X DELETE` の頭は gh になりうる。
		for _, word := range words[:jsSlice(len(words), offset+1)] {
			if word.literal == nil {
				setReason(ghAPIUnreadableReason)
				return true
			}
		}

		isGh := len(stripped) > 0 && stripped[0] == "gh"
		// サブコマンドの位置が展開なら gh api になりうる。`gh a${P}i r -X DELETE`。
		if sub := offset + 1; isGh && sub >= 0 && sub < len(words) && words[sub].literal == nil {
			setReason(ghAPIUnreadableReason)
			return true
		}

		if isGh && len(stripped) > 1 && stripped[1] == "api" {
			seen = true
			setReason(ghAPIArgvReason(words[jsSlice(len(words), offset+2):]))
			return true
		}
		if hidesGhAPI(stripped) {
			setReason(ghAPIIndirectReason)
		}
		return true
	})

	// gh api と無関係なコマンドに ask を返すと、確認を減らすためのフックが確認を増やす。
	// 生の文字列でなく wordText で探すのは、a"pi" や行継続を挟んだ ap\<改行>i も
	// bash では api になるため。字面の gh の直後が展開なら api になりうるので残す。
	// gh まで展開に隠した形はここで抜けるが、フックが無い場合と同じ扱いになる。
	switch {
	case !seen && !mayBeAPI:
		return ghAPIDecision{}, false
	case reason == ghAPINoMethodReason:
		return ghAPIDecision{"deny", reason}, true
	case reason != "":
		return ghAPIDecision{"ask", reason}, true
	case seen:
		return ghAPIDecision{"allow", ghAPIAllowReason}, true
	}
	return ghAPIDecision{}, false
}

// checkGhAPI は判定を返す。判定を出さないなら false。
func checkGhAPI(command string) (ghAPIDecision, bool) {
	file, err := parse(command)
	if err != nil {
		// 解析できないコマンドにも if ゲートは反応する。gh api が見当たらなければ
		// 判定する対象が無いので黙って通す。
		if ghAPIText.MatchString(command) {
			return ghAPIDecision{"ask", ghAPIUnparsedReason}, true
		}
		return ghAPIDecision{}, false
	}
	return ghAPIDecide(file)
}
