package main

import (
	"regexp"
	"strconv"
	"strings"

	"mvdan.cc/sh/v3/syntax"

	"claude-bash-guard/rules"
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

func stripWrappers(args []string) []string {
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
