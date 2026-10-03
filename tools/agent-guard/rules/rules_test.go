package rules

// 変換器と banned-commands.json の方言を直接検証する。
//
// check-regex-dialect.sh は文字クラスの包含と corpus の判定を見るが、corpus は
// 両方言で判定が一致する入力だけなので、包含の向きが変わらない範囲の変換ミスを
// 通してしまう。特に [:alnum:] は corpus のどの行にも現れない。ここでは変換
// 結果そのものと、JSON の方言を見る。

import (
	"regexp"
	"testing"
)

func TestConvert(t *testing.T) {
	cases := map[string]string{
		"a[[:space:]]+b":    "a[" + SpaceClass + "]+b",
		"([^[:alnum:]_]|$)": "([^A-Za-z0-9_]|$)",
		"[[:alnum:]]":       "[A-Za-z0-9]",
	}
	for in, want := range cases {
		if got := Convert(in); got != want {
			t.Errorf("Convert(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestEveryRuleConverts(t *testing.T) {
	ruleSet, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	posixClass := regexp.MustCompile(`\[:[a-z]+:\]`)
	for _, rule := range ruleSet {
		if converted := Convert(rule.Pattern); posixClass.MatchString(converted) {
			t.Errorf("POSIX class survived conversion: %s", converted)
		}
	}
}

// 許可する POSIX クラスを 2 つに限るのは、Convert が知っているのがこの 2 つ
// だけだからである。3 つ目を JSON へ足すと、Go の ASCII だけの同名クラスとして
// 黙って解釈され、locale の集合より狭くなる。
func TestRulesUseOnlyKnownClasses(t *testing.T) {
	ruleSet, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	known := map[string]bool{"[:space:]": true, "[:alnum:]": true}
	posixClass := regexp.MustCompile(`\[:[a-z]+:\]`)
	for _, rule := range ruleSet {
		for _, found := range posixClass.FindAllString(rule.Pattern, -1) {
			if !known[found] {
				t.Errorf("unknown POSIX class %s in: %s", found, rule.Pattern)
			}
		}
	}
}

// Go 固有の構文が混ざると、正本が POSIX ERE でなくなる。bash の ERE は \s も
// \d も lookaround も解釈しないので、混ざった時点で両方言で読める状態が失われる。
func TestRulesCarryNoNonPOSIXSyntax(t *testing.T) {
	ruleSet, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	forbidden := map[string]*regexp.Regexp{
		`a \s / \d / \w style shorthand`: regexp.MustCompile(`\\[sSdDwWbB]`),
		"a lookaround or flag group":     regexp.MustCompile(`\(\?`),
		"a Unicode property escape":      regexp.MustCompile(`\\[pP]`),
		`a \x{...} escape`:               regexp.MustCompile(`\\x`),
	}
	for _, rule := range ruleSet {
		for what, re := range forbidden {
			if re.MatchString(rule.Pattern) {
				t.Errorf("%s in: %s", what, rule.Pattern)
			}
		}
	}
}
