// Package rules は banned-commands.json のテキストパターンを扱う。単一の
// CallExpr に紐づけられない形 (パイプ先、リダイレクト先、代入の前置) を見る。
//
// 標準ライブラリ以外を import しない。cmd/regex-dialect を `go run` するときに
// シェルの parser を取ってこずに済ませるためである。
package rules

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

// banned-commands.json の正本方言は POSIX ERE である。JSON を Go の構文へ
// 書き換えないこと。scripts/check-regex-dialect.sh が同じパターンを bash の =~
// でも照合し、両者を突き合わせている。
//
//go:embed banned-commands.json
var rulesJSON []byte

// SpaceClass は POSIX の [:space:] の代わりに置く bracket expression の中身。
// Go の [[:space:]] と \s は ASCII にしか一致しないが、UTF-8 locale の C
// ライブラリの集合はそうではなく、そこで取りこぼすと禁止コマンドが通る。
// 中身は ECMAScript の \s と同じ集合で、locale の集合を包含することは
// check-regex-dialect.sh が確かめる。
const SpaceClass = `\t\n\v\f\r \x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}\x{feff}`

// JQSpaceClass は jq (Oniguruma) の [[:space:]] に合わせた集合で、jq だけが
// U+0085 にも一致する。env -S の分割は jq のプログラムから書き写したので、
// 区切りはこの集合を包含していなければならない。check-regex-dialect.sh が確かめる。
const JQSpaceClass = SpaceClass + `\x{85}`

// Convert は banned-commands.json の POSIX ERE を Go の構文へ書き換える。
// 変換は過剰に一致する向きへ倒す。ブロックが増えることはあっても減らない。
func Convert(pattern string) string {
	return strings.NewReplacer(
		"[:space:]", SpaceClass,
		"[:alnum:]", "A-Za-z0-9",
	).Replace(pattern)
}

type Rule struct {
	Pattern string `json:"pattern"`
	Message string `json:"message"`
	re      *regexp.Regexp
}

// Load は埋め込んだルールを読む。ここで失敗したら全コマンドをブロックする
// 必要があるので、init で panic せずに error を返し、main に報告させる。
func Load() ([]Rule, error) {
	var rules []Rule
	if err := json.Unmarshal(rulesJSON, &rules); err != nil {
		return nil, fmt.Errorf("banned-commands.json: %w", err)
	}
	for i := range rules {
		re, err := regexp.Compile(Convert(rules[i].Pattern))
		if err != nil {
			return nil, fmt.Errorf("banned-commands.json: %w", err)
		}
		rules[i].re = re
	}
	return rules, nil
}

// Match はコマンドが最初に一致したルールのメッセージを返す。
func Match(command string, rules []Rule) (string, bool) {
	for _, rule := range rules {
		if rule.re.MatchString(command) {
			return rule.Message, true
		}
	}
	return "", false
}
