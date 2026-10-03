package main

import (
	"regexp"
	"slices"
)

// Herdr の入力系コマンドを、シェルコマンドの境界 (制御構文のキーワードと
// よく使うラッパーを含む) で字面のまま探す。ベストエフォートのガードであり
// セキュリティ境界ではない。任意の Bash ならコマンドを隠すことも、ソケットへ
// 直接触れることもできる。
var herdrInput = func() *regexp.Regexp {
	const (
		shellWord       = `[^;&|(){}[:space:]]+`
		wrapperOption   = `--?[^;&|(){}[:space:]]+`
		wrapperArgument = `[^;&|(){}[:space:]-][^;&|(){}[:space:]]*`
		wrapperName     = `([^;&|(){}[:space:]]*/)?(env|command|exec|xargs|sudo|nohup|time|builtin)`
		wrapper         = wrapperName + `[[:space:]]+((` + wrapperOption + `)[[:space:]]+((` + wrapperArgument + `)[[:space:]]+)?)*`
		control         = `((then|do|else|elif|if|while|until|!)[[:space:]]+)*`
	)
	return regexp.MustCompile(`(^|[;&|(){}\n])[[:space:]]*` + control +
		`(` + wrapper + `|[A-Za-z_][A-Za-z0-9_]*=` + shellWord + `[[:space:]]+)*` +
		`([^;&|(){}[:space:]]*/)?herdr[[:space:]]+(agent[[:space:]]+(prompt|send-keys)|pane[[:space:]]+(send-text|send-keys|run))([;&|(){}[:space:]]|$)`)
}()

const herdrInputMessage = "Use herdr-peer instead of raw Herdr input commands so the same-tab peer checks are applied."

// 字面の正規表現と AST の判定の両方で見る。AST はラッパーの奥
// (`timeout 5 herdr ...`) や sh -c の文字列の中まで届き、正規表現は解析できない
// 入力にも効く。
func herdrInputCommand(command string, verdicts []verdict) bool {
	return herdrInput.MatchString(command) || slices.Contains(verdicts, "HERDR_INPUT")
}
