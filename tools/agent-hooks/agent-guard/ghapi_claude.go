package main

// gh-api モード: Claude Code の `gh api` が GET を明示した読み取りだと証明できた
// ときだけ allow を返す PreToolUse 判定。証明できなければ ask へ落とす。ただし
// メソッドの書き忘れと、展開が旗を持ち込める書き方は deny にする。ask の理由は
// ユーザーにしか見えず、deny の理由だけが Claude に届くので、deny なら Claude が
// -X GET を足したり展開を引用したりして自分で再実行できる。
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

	"agent-hooks/agent-guard/rules"
)

// gh api の短オプション。値を取る文字を取り違えると束の解釈が壊れる。真偽値を
// 値を取る側に入れると `-iF a=b` の F が i に食われて POST が素通りするので、
// `gh api --help` が値を取ると書いている文字だけを入れる。値を取る側の表は
// ghapi.go の ghAPIShortValue / ghAPILongValue を使う。
const (
	ghAPIShortBool = "i"
	ghAPIShortBody = "F"
)

var ghAPILongBool = map[string]bool{
	"allow-escape-sequences": true, "help": true, "include": true, "paginate": true,
	"silent": true, "slurp": true, "verbose": true,
}

// -f/--raw-field は明示した GET ではクエリ文字列になるので、ここに入れない。
// -F は @path でローカルファイルを、--input は GET でもボディを送る。
var ghAPILongBody = map[string]bool{"field": true, "input": true}

const (
	ghAPIBodyReason       = "gh api: body-bearing flag (-f/-F/--field/--raw-field/--input) implies POST"
	ghAPINonLiteralReason = `gh api: an expanded argument could add a flag — write flag names literally and double-quote each expansion (gh api -X GET "repos/$repo" -H "$h"); an endpoint that starts with an expansion goes last, after -- (gh api -X GET --jq . -- "$url")`
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
	rawField   bool
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
			return ghAPICluster{eatsNext: glued == "", valueTaken: true, rawField: letter == 'f'}
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
// 2 つ目の戻り値は -f/--raw-field を読んだかどうか。
func ghAPIExpansionReason(word ghAPIWord) (string, bool) {
	if word.splittable || word.prefix == "" {
		return ghAPINonLiteralReason, false
	}
	if !strings.HasPrefix(word.prefix, "-") {
		return "", false
	}
	if strings.HasPrefix(word.prefix, "--") {
		name, _, _ := strings.Cut(word.prefix[2:], "=")
		switch {
		case ghAPILongBody[name]:
			return ghAPIBodyReason, false
		case name == "method":
			return ghAPIMethodReason(nil), false
		case ghAPILongValue[name] || ghAPILongBool[name]:
			return "", name == "raw-field"
		}
		return ghAPINonLiteralReason, false
	}
	cluster := ghAPIShortCluster(word.prefix[1:], nil)
	if cluster.reason != "" {
		return cluster.reason, false
	}
	// 真偽値の文字だけで字面が尽きた。展開が X や F を足せる。
	if !cluster.valueTaken {
		return ghAPINonLiteralReason, false
	}
	return "", cluster.rawField
}

// gh api の後ろの argv を歩き、読み取りと証明できなければ理由を返す。
func ghAPIArgvReason(words []ghAPIWord) string {
	endOfOptions := false
	sawGet := false
	rawField := false
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
			reason, raw := ghAPIExpansionReason(word)
			if reason != "" {
				return reason
			}
			rawField = rawField || raw
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
			rawField = rawField || name == "raw-field"
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
		rawField = rawField || cluster.rawField
		if cluster.eatsNext {
			if !eats(i) {
				return ghAPINonLiteralReason
			}
			i++
		}
	}

	// メソッドを書かない -f は gh が POST に切り替える。
	if !sawGet && rawField {
		return ghAPIBodyReason
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

// allow はコマンド全体の確認を飛ばすので、gh api と並ぶ部分も副作用が無いと
// 証明できなければならない。引数をどう与えても書き込みも実行もしないコマンドだけを
// 置く。printf (-v で変数を書く)、date (--set)、sort (-o)、rg (--pre)、find、awk、
// sed は入れない。test と [ は引数の形を ghAPISafeTest で確かめる。
var ghAPICompanions = map[string]bool{
	"cat": true, "cut": true, "echo": true, "false": true, "grep": true, "head": true,
	"jq": true, "sleep": true, "tail": true, "tr": true, "true": true, "wc": true,
}

// bash は名前の添字や算術比較の被演算子を算術式として評価し、その中の $(…) を
// 実行する (`test -v 'a[$(cmd)0]'`、`[[ 'a[$(cmd)0]' -eq 1 ]]`)。値に置いた文字列でも
// 起きるので、評価の入口になる演算子と展開の形をすべて断つ。
func ghAPISafeTest(args []*syntax.Word) bool {
	// 引数の数で形が決まるので、語を増減させる展開は認めない。引用の中の $(…) は
	// 1 語のままなので通す。readGhAPIWord の splittable はこれも分割扱いにする。
	if ghAPIHasGlob(args[1:]) {
		return false
	}
	words := make([]ghAPIWord, len(args))
	for i, arg := range args {
		words[i] = readGhAPIWord(arg)
		for _, part := range arg.Parts {
			switch part := part.(type) {
			case *syntax.Lit, *syntax.SglQuoted:
			case *syntax.DblQuoted:
				for _, inner := range part.Parts {
					if exp, ok := inner.(*syntax.ParamExp); ok && exp.Param != nil &&
						(exp.Param.Value == "@" || exp.Param.Value == "*") {
						return false
					}
				}
			default:
				return false
			}
		}
	}
	lit := func(w ghAPIWord) string {
		if w.literal == nil {
			return "\x00"
		}
		return *w.literal
	}
	ops := words[1:]
	if lit(words[0]) == "[" {
		if len(ops) == 0 || lit(ops[len(ops)-1]) != "]" {
			return false
		}
		ops = ops[:len(ops)-1]
	}
	// 引数の数で形が決まる (POSIX test)。1 個なら空でないかの判定だけになる。
	switch len(ops) {
	case 0, 1:
		return true
	case 2:
		op := lit(ops[0])
		return op == "-z" || op == "-n" || op == "!"
	case 3:
		op := lit(ops[1])
		return op == "=" || op == "==" || op == "!="
	}
	return false
}

func ghAPISafeParamExp(p *syntax.ParamExp) bool {
	// ${!x} と ${a[i]} は値を名前や添字として評価し、${x@P} は値を展開し直す。
	if p.Excl || p.Index != nil || p.Slice != nil || p.Names != 0 || p.Flags != nil ||
		p.NestedParam != nil || p.Modifiers != nil {
		return false
	}
	if p.Exp == nil {
		return true
	}
	switch p.Exp.Op {
	case syntax.DefaultUnset, syntax.DefaultUnsetOrNull, syntax.AlternateUnset, syntax.AlternateUnsetOrNull,
		syntax.RemSmallSuffix, syntax.RemLargeSuffix, syntax.RemSmallPrefix, syntax.RemLargePrefix:
		return true
	}
	return false
}

// zsh ではこれらへの代入が PATH などの配列を書き換える。
var ghAPITiedNames = map[string]bool{
	"cdpath": true, "fpath": true, "mailpath": true, "manpath": true, "module_path": true, "path": true,
}

// 大文字を含む名前は環境変数として子に渡りうるので認めない。
func ghAPISafeName(name string) bool {
	return name == strings.ToLower(name) && !ghAPITiedNames[name]
}

func ghAPISafeAssigns(assigns []*syntax.Assign) bool {
	for _, a := range assigns {
		if !ghAPISafeName(a.Name.Value) || a.Index != nil {
			return false
		}
	}
	return true
}

// 引用されていない glob はファイル名に展開され、語の数も中身も作業ディレクトリ
// 次第になる (`-v` や `--method=DELETE` という名前のファイル)。^ # ~ は zsh の
// EXTENDED_GLOB で glob になる。
func ghAPIHasGlob(words []*syntax.Word) bool {
	for _, word := range words {
		for _, part := range word.Parts {
			if lit, ok := part.(*syntax.Lit); ok && strings.ContainsAny(lit.Value, "*?[{^#~") {
				return true
			}
		}
	}
	return false
}

// `--` の後ろの語は ghAPIArgvReason が見ないので、置換の出力が URL に入る。
// `-- "repos/o/r?q=$(cat ~/.ssh/id_rsa)"` は秘密を GET で送れる。
func ghAPIHasSubst(call *syntax.CallExpr) bool {
	found := false
	syntax.Walk(call, func(node syntax.Node) bool {
		switch node.(type) {
		case *syntax.CmdSubst, *syntax.ProcSubst:
			found = true
		}
		return !found
	})
	return found
}

// /dev/null への出力と fd の複製だけを認める。`>& file` はファイルへ書くので、
// 複製先は数字か - に限る。
func ghAPISafeRedirect(r *syntax.Redirect) bool {
	target := readGhAPIWord(r.Word).literal
	if target == nil {
		return false
	}
	switch r.Op {
	case syntax.RdrOut, syntax.AppOut, syntax.RdrAll, syntax.AppAll, syntax.ClbOut:
		return *target == "/dev/null"
	case syntax.DplOut, syntax.DplIn:
		return *target == "-" || *target != "" && strings.Trim(*target, "0123456789") == ""
	}
	return false
}

// 前置きの wrapper が環境を書き換える形 (`env PATH=/x gh api`, `env -S'PATH=/x gh api'`)。
func ghAPISetsEnv(texts []string) bool {
	for _, text := range texts {
		if text == "gh" {
			return false
		}
		if strings.Contains(text, "=") {
			return true
		}
	}
	return false
}

// ghCalls は ghAPIDecide が読み取りと確かめた gh api 呼び出し。知らない構文は
// 安全と証明できないので、型の許可リストで歩く。
func ghAPIOnlySafe(file *syntax.File, ghCalls map[*syntax.CallExpr]bool) bool {
	safe := true
	syntax.Walk(file, func(node syntax.Node) bool {
		if !safe {
			return false
		}
		switch node := node.(type) {
		case nil, *syntax.File, *syntax.Comment, *syntax.BinaryCmd, *syntax.Block, *syntax.Subshell,
			*syntax.IfClause, *syntax.WhileClause, *syntax.ForClause,
			*syntax.TimeClause, *syntax.TestClause, *syntax.ParenTest, *syntax.Word, *syntax.Lit,
			*syntax.SglQuoted, *syntax.DblQuoted, *syntax.CmdSubst, *syntax.Redirect:
		case *syntax.BinaryTest:
			switch node.Op {
			case syntax.AndTest, syntax.OrTest, syntax.TsMatchShort, syntax.TsMatch, syntax.TsNoMatch:
			default:
				safe = false
			}
		case *syntax.UnaryTest:
			safe = node.Op == syntax.TsEmpStr || node.Op == syntax.TsNempStr || node.Op == syntax.TsNot
		case *syntax.Stmt:
			for _, r := range node.Redirs {
				safe = safe && ghAPISafeRedirect(r)
			}
		case *syntax.ParamExp:
			safe = ghAPISafeParamExp(node)
		case *syntax.WordIter:
			// for と select のループ変数も代入になる。
			safe = ghAPISafeName(node.Name.Value)
		case *syntax.Assign:
			// 中身は CallExpr 側で確かめ、値の語は続けて歩く。
		case *syntax.CallExpr:
			switch {
			case len(node.Args) == 0:
				safe = ghAPISafeAssigns(node.Assigns)
			case len(node.Assigns) > 0:
				safe = false
			case ghCalls[node]:
				safe = !ghAPIHasSubst(node) && !ghAPIHasGlob(node.Args)
			default:
				name := readGhAPIWord(node.Args[0]).literal
				switch {
				case name == nil:
					safe = false
				case *name == "test" || *name == "[":
					safe = ghAPISafeTest(node.Args)
				default:
					safe = ghAPICompanions[*name]
				}
			}
		default:
			safe = false
		}
		return safe
	})
	return safe
}

func ghAPIDecide(file *syntax.File) (ghAPIDecision, bool) {
	seen := false
	mayBeAPI := false
	reason := ""
	ghCalls := map[*syntax.CallExpr]bool{}
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
			if !ghAPISetsEnv(texts) {
				ghCalls[call] = true
			}
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
	case reason == ghAPINoMethodReason, reason == ghAPINonLiteralReason:
		return ghAPIDecision{"deny", reason}, true
	case reason != "":
		return ghAPIDecision{"ask", reason}, true
	// 並ぶ部分を証明できない読み取りは判定を出さず、通常の確認に任せる。
	case seen && ghAPIOnlySafe(file, ghCalls):
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
