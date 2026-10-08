package main

import (
	"path"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"mvdan.cc/sh/v3/syntax"

	"agent-guard/rules"
)

// 移植元の TypeScript の正規表現では `.` が改行類 (\n \r U+2028 U+2029) に一致
// しない。Go の `.` は \n だけを除くので、同じ集合を明示して判定を揃える。
const jsDot = `[^\n\r\x{2028}\x{2029}]`

// --- 語の展開 -------------------------------------------------------------

var ansiToken = regexp.MustCompile(
	`\\x[0-9a-fA-F]{1,2}|\\u[0-9a-fA-F]{1,4}|\\U[0-9a-fA-F]{1,8}|\\[0-7]{1,3}|\\(?s:.)|[^\\]+`,
)

var ansiShorthand = map[string]string{
	"n": "\n",
	"t": "\t",
	"r": "\r",
	"a": "\a",
	"b": "\b",
	"e": "\x1b",
	"f": "\f",
	"v": "\v",
}

// $'...' の中身を展開する。読めない符号位置 (範囲外や、\x の後ろに 16 進数が
// 無いもの) があれば入力文字列をそのまま返す。この差が禁止判定を変えないことは
// testdata/banned-cases.json が固定している。
func ansiDecode(value string) string {
	var b strings.Builder
	for _, token := range ansiToken.FindAllString(value, -1) {
		switch {
		case len(token) >= 2 && token[0] == '\\' && strings.ContainsRune("xuU", rune(token[1])):
			cp, err := strconv.ParseUint(token[2:], 16, 32)
			if err != nil || cp > 0x10ffff {
				return value
			}
			b.WriteRune(rune(cp))
		case len(token) >= 2 && token[0] == '\\' && token[1] >= '0' && token[1] <= '7':
			cp, _ := strconv.ParseUint(token[1:], 8, 32)
			b.WriteRune(rune(cp))
		case token[0] == '\\':
			if s, ok := ansiShorthand[token[1:]]; ok {
				b.WriteString(s)
			} else {
				b.WriteString(token[1:])
			}
		default:
			b.WriteString(token)
		}
	}
	return b.String()
}

// AST の語を文字列に戻す。展開結果が分からない部分 (ParamExp、CmdSubst など) は
// 空文字になるので、`"$x"rm` は `rm` として読まれる。Lit はバックスラッシュを
// すべて落とすため `r\m` も `rm` になる。取りこぼすより過剰に一致させる側へ倒す。
func wordText(word *syntax.Word) string {
	var b strings.Builder
	for _, part := range word.Parts {
		switch part := part.(type) {
		case *syntax.Lit:
			b.WriteString(strings.ReplaceAll(part.Value, `\`, ""))
		case *syntax.SglQuoted:
			if part.Dollar {
				b.WriteString(ansiDecode(part.Value))
			} else {
				b.WriteString(part.Value)
			}
		case *syntax.DblQuoted:
			for _, inner := range part.Parts {
				if lit, ok := inner.(*syntax.Lit); ok {
					b.WriteString(lit.Value)
				}
			}
		}
	}
	return b.String()
}

// 語を bash が実際に渡す文字列へ戻す。sh -c の文字列を解析し直すために使う。
// wordText と違い引用の規則どおりにバックスラッシュを外すので、"echo \"a; b\""
// の中のセミコロンは区切りにならない。展開の部分は wordText と同じく空文字になる。
func scriptText(word *syntax.Word) string {
	var b strings.Builder
	for _, part := range word.Parts {
		switch part := part.(type) {
		case *syntax.Lit:
			b.WriteString(unescape(part.Value, func(byte) bool { return true }))
		case *syntax.SglQuoted:
			if part.Dollar {
				b.WriteString(ansiDecode(part.Value))
			} else {
				b.WriteString(part.Value)
			}
		case *syntax.DblQuoted:
			for _, inner := range part.Parts {
				if lit, ok := inner.(*syntax.Lit); ok {
					b.WriteString(unescape(lit.Value, func(c byte) bool {
						return strings.IndexByte("$`\"\\", c) >= 0
					}))
				}
			}
		}
	}
	return b.String()
}

// バックスラッシュと次の 1 文字のうち、escapes が真を返す文字ならバックスラッシュを
// 落とす。改行が続く場合は行継続なので両方を落とす。
func unescape(value string, escapes func(byte) bool) string {
	var b strings.Builder
	for i := 0; i < len(value); i++ {
		if value[i] == '\\' && i+1 < len(value) {
			switch next := value[i+1]; {
			case next == '\n':
				i++
				continue
			case escapes(next):
				i++
			}
		}
		b.WriteByte(value[i])
	}
	return b.String()
}

// env -S の値の分割を模す。空白と引用符外の \_ が引数区切りで、"..." と '...' の
// 引用とバックスラッシュエスケープを解く。ダブルクォート内の \_ は引数内の空白に
// なる。区切りもトークンとして取り出してから捨てることで、\_ の _ が次の語へ
// 接着するのを防ぐ。展開結果は env のオプションとして読み直す。
var (
	sSplitToken = regexp.MustCompile(
		`\\_|[` + rules.JQSpaceClass + `]+|(?:[^` + rules.JQSpaceClass + `"'\\]|\\[^_]|"(?:[^"\\]|\\(?s:.))*"|'[^']*')+`,
	)
	sSplitSeparator = regexp.MustCompile(`^(?:\\_|[` + rules.JQSpaceClass + `]+)$`)
	sSplitDouble    = regexp.MustCompile(`"((?:[^"\\]|\\(?s:.))*)"`)
	sSplitSingle    = regexp.MustCompile(`'([^']*)'`)
	sSplitEscape    = regexp.MustCompile(`\\((?s:.))`)
)

func sSplit(value string) []string {
	var out []string
	for _, token := range sSplitToken.FindAllString(value, -1) {
		if sSplitSeparator.MatchString(token) {
			continue
		}
		token = sSplitDouble.ReplaceAllStringFunc(token, func(m string) string {
			return strings.ReplaceAll(m[1:len(m)-1], `\_`, " ")
		})
		token = sSplitSingle.ReplaceAllStringFunc(token, func(m string) string {
			return m[1 : len(m)-1]
		})
		token = sSplitEscape.ReplaceAllString(token, "$1")
		out = append(out, token)
	}
	return out
}

// --- オプション列の走査 ---------------------------------------------------

// 短オプションは束ねられる ("sudo -nu root")。左から見て、値を取る文字が末尾に
// あれば次の語を食べ、途中にあれば残りが付属値になる。
func clusterEats(cluster, argChars string) bool {
	for i := 0; i < len(cluster); i++ {
		if strings.IndexByte(argChars, cluster[i]) >= 0 {
			return i == len(cluster)-1
		}
	}
	return false
}

func drop(args []string, n int) []string {
	if n >= len(args) {
		return nil
	}
	return args[n:]
}

func prepend(head []string, rest []string) []string {
	return append(append([]string{}, head...), rest...)
}

var (
	pCluster      = regexp.MustCompile(`^-p+$`)
	envCluster    = regexp.MustCompile(`^-[A-Za-z0]+$`)
	envAttachedS  = regexp.MustCompile(`^-[i0v]*S(` + jsDot + `*)$`)
	assignment    = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)
	letterCluster = regexp.MustCompile(`^-[A-Za-z]+$`)
)

// 束の中に -v/-V があるとコマンドを実行しなくなるので、純粋な -p の束だけ剥がす。
// "--" の次はオプションに見えてもコマンド名なので、そこで剥がすのをやめる。
func stripCommandOpts(args []string) []string {
	for len(args) > 0 {
		if args[0] == "--" {
			return args[1:]
		}
		if !pCluster.MatchString(args[0]) {
			return args
		}
		args = args[1:]
	}
	return args
}

func stripEnvOpts(args []string) []string {
	for len(args) > 0 {
		head := args[0]
		next := ""
		if len(args) > 1 {
			next = args[1]
		}
		switch {
		case head == "-u" || head == "-C" || head == "--unset" || head == "--chdir":
			args = drop(args, 2)
		case head == "-S" || head == "--split-string":
			args = prepend(sSplit(next), drop(args, 2))
		case strings.HasPrefix(head, "--split-string="):
			args = prepend(sSplit(head[len("--split-string="):]), args[1:])
		case envAttachedS.MatchString(head):
			if attached := envAttachedS.FindStringSubmatch(head)[1]; attached == "" {
				args = prepend(sSplit(next), drop(args, 2))
			} else {
				args = prepend(sSplit(attached), args[1:])
			}
		case envCluster.MatchString(head):
			if clusterEats(head[1:], "uC") {
				args = drop(args, 2)
			} else {
				args = args[1:]
			}
		case strings.HasPrefix(head, "-") || assignment.MatchString(head):
			args = args[1:]
		default:
			return args
		}
	}
	return args
}

var sudoValueOpts = map[string]bool{
	"--chdir":           true,
	"--chroot":          true,
	"--close-from":      true,
	"--command-timeout": true,
	"--group":           true,
	"--host":            true,
	"--other-user":      true,
	"--prompt":          true,
	"--role":            true,
	"--type":            true,
	"--user":            true,
}

func stripSudoOpts(args []string) []string {
	for len(args) > 0 {
		head := args[0]
		switch {
		case head == "--":
			return args[1:]
		case sudoValueOpts[head]:
			args = drop(args, 2)
		case letterCluster.MatchString(head):
			if clusterEats(head[1:], "aCDghprRtTuU") {
				args = drop(args, 2)
			} else {
				args = args[1:]
			}
		case strings.HasPrefix(head, "-") || assignment.MatchString(head):
			args = args[1:]
		default:
			return args
		}
	}
	return args
}

func stripExecOpts(args []string) []string {
	for len(args) > 0 {
		head := args[0]
		switch {
		case head == "--":
			return args[1:]
		case letterCluster.MatchString(head):
			if clusterEats(head[1:], "a") {
				args = drop(args, 2)
			} else {
				args = args[1:]
			}
		case strings.HasPrefix(head, "-"):
			args = args[1:]
		default:
			return args
		}
	}
	return args
}

// 値を別語で取る短オプションの文字と長オプションを渡し、コマンドの手前の
// オプション列を剥がす。"--" の次はオプションに見えてもコマンドとして扱う。
func stripOpts(args []string, valueShort string, valueLong []string) []string {
	for len(args) > 0 {
		head := args[0]
		switch {
		case head == "--":
			return args[1:]
		case strings.HasPrefix(head, "--"):
			if !strings.Contains(head, "=") && slices.Contains(valueLong, head) {
				args = drop(args, 2)
			} else {
				args = args[1:]
			}
		case shortCluster.MatchString(head) && clusterEats(head[1:], valueShort):
			args = drop(args, 2)
		case strings.HasPrefix(head, "-"):
			args = args[1:]
		default:
			return args
		}
	}
	return args
}

var shortCluster = regexp.MustCompile(`^-[A-Za-z0-9]+$`)

// /bin/rm も ./rm も rm として読む。同名の自作スクリプトまで止めるが、取りこぼす
// より過剰に一致させる側へ倒す。
func commandName(word string) string {
	// zsh は `=rm` を rm の実行ファイルのパスへ展開する。
	if len(word) > 1 && word[0] == '=' {
		word = word[1:]
	}
	if strings.Contains(word, "/") {
		return path.Base(word)
	}
	return word
}

// GNU xargs の長いオプションと、別の語の値を取るか。
var xargsLong = map[string]bool{
	"--arg-file": true, "--delimiter": true, "--max-lines": true, "--max-args": true,
	"--max-procs": true, "--max-chars": true, "--process-slot-var": true,
	"--null": false, "--eof": false, "--replace": false, "--open-tty": false, "--interactive": false,
	"--no-run-if-empty": false, "--show-limits": false, "--verbose": false, "--exit": false,
	"--help": false, "--version": false,
}

// 省略形を一意に決まる長いオプションへ戻す。曖昧なら xargs が失敗するので "" を返す。
func xargsLongOpt(word string) string {
	name, _, _ := strings.Cut(word, "=")
	if _, ok := xargsLong[name]; ok {
		return name
	}
	match := ""
	for full := range xargsLong {
		if strings.HasPrefix(full, name) {
			if match != "" {
				return ""
			}
			match = full
		}
	}
	return match
}

// xargs のオプションを剥がしながら、-a/--arg-file があるかを返す。引数を
// ファイルから読むと、子は xargs の標準入力を受け継ぐ。値は英数字以外も
// 含めて束に付くので (-a./list)、shortCluster では束を見分けない。
func stripXargsOpts(args []string) (_ []string, argFile bool) {
	for len(args) > 0 {
		head := args[0]
		switch {
		case head == "--":
			return args[1:], argFile
		case strings.HasPrefix(head, "--"):
			name := xargsLongOpt(head)
			argFile = argFile || name == "--arg-file"
			if !strings.Contains(head, "=") && xargsLong[name] {
				args = drop(args, 2)
			} else {
				args = args[1:]
			}
		case strings.HasPrefix(head, "-"):
			i := strings.IndexAny(head[1:], "adEILnPsRSJ")
			argFile = argFile || i >= 0 && head[1+i] == 'a'
			if i >= 0 && i == len(head)-2 {
				args = drop(args, 2)
			} else {
				args = args[1:]
			}
		default:
			return args, argFile
		}
	}
	return args, argFile
}

func stripWrappers(args []string) []string {
	args, _ = unwrap(args)
	return args
}

// viaXargs は、子の標準入力を /dev/null にする xargs を剥がしたか。
func unwrap(args []string) (_ []string, viaXargs bool) {
	for len(args) > 0 {
		switch commandName(args[0]) {
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
		case "busybox", "noglob", "nocorrect", "-":
			args = args[1:]
		case "repeat":
			args = drop(args, 2)
		case "foreach":
			// zsh の `foreach NAME (LIST) CMD...; end`。LIST は 1 語として届く。
			// 本体が次の行以降にあれば、それは別の CallExpr として判定される。
			if len(args) < 3 || !strings.HasPrefix(args[2], "(") {
				return args, viaXargs
			}
			args = args[3:]
		case "nohup", "setsid":
			args = stripOpts(args[1:], "", nil)
		case "nice":
			args = stripOpts(args[1:], "n", []string{"--adjustment"})
		case "timeout":
			// オプションの後ろの 1 語は時間で、その次がコマンドになる。
			args = drop(stripOpts(args[1:], "sk", []string{"--signal", "--kill-after"}), 1)
		case "time":
			args = stripOpts(args[1:], "of", []string{"--output", "--format"})
		case "xargs":
			var argFile bool
			args, argFile = stripXargsOpts(args[1:])
			viaXargs = viaXargs || !argFile
		case "stdbuf":
			args = stripOpts(args[1:], "ioe", []string{"--input", "--output", "--error"})
		case "caffeinate":
			args = stripOpts(args[1:], "tw", nil)
		default:
			return append([]string{commandName(args[0])}, args[1:]...), viaXargs
		}
	}
	return args, viaXargs
}
