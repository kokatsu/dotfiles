// regex-dialect は banned-commands.json の POSIX ERE を Go へ変換したときの差を
// 測る。scripts/check-regex-dialect.sh が使う Go 側の半分。
//
//	space-set     stdout: [:space:] の変換先が一致する符号位置 (U+XXXX、1 行 1 個)
//	jq-space-set  stdout: env -S の区切りが一致する符号位置 (同上)
//	match-corpus  stdin: 判定したいコマンド行
//	              stdout: "BLOCK<TAB>行" または "allow<TAB>行"
//
// 対になる POSIX 側の走査と突き合わせは check-regex-dialect.sh が行う。変換器と
// 文字クラスはフックの rules パッケージのものを使う。ここで複製すると、実際に
// 使われる方と検査する方が別々に腐る。
package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"

	"claude-bash-guard/rules"
)

func printSet(class string) {
	re := regexp.MustCompile(`^[` + class + `]$`)
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	for cp := rune(1); cp <= 0xffff; cp++ {
		if cp >= 0xd800 && cp <= 0xdfff {
			continue
		}
		if re.MatchString(string(cp)) {
			fmt.Fprintf(w, "U+%04X\n", cp)
		}
	}
}

func matchCorpus() error {
	ruleSet, err := rules.Load()
	if err != nil {
		return err
	}
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		verdict := "allow"
		if _, ok := rules.Match(line, ruleSet); ok {
			verdict = "BLOCK"
		}
		fmt.Printf("%s\t%s\n", verdict, line)
	}
	return scanner.Err()
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: regex-dialect {space-set|jq-space-set|match-corpus}")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "space-set":
		printSet(rules.SpaceClass)
	case "jq-space-set":
		printSet(rules.JQSpaceClass)
	case "match-corpus":
		if err := matchCorpus(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: regex-dialect {space-set|jq-space-set|match-corpus}")
		os.Exit(2)
	}
}
