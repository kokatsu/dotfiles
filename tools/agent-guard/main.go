// agent-guard は Claude Code と Codex の PreToolUse フック。
// stdin で hook payload を受け取り、ブロックするなら理由を stderr に出して
// exit 2 で終わる。
//
//	agent-guard banned         Claude Code の Bash 用。Herdr 入力ガードと禁止コマンド
//	agent-guard codex          Codex の Bash 用。Herdr 入力ガードと禁止コマンド (GREP_R を除く)
//	agent-guard managed-paths  Claude Code の Edit/Write 用。Home Manager の管理下を守る
//
// どれもガードなので、判定に届かなかった失敗はすべて exit 2 にする。
// Claude Code と Codex は exit 2 だけをブロックとして扱い、それ以外の失敗では
// コマンドを通してしまう。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/signal"
	"slices"
	"strings"
	"syscall"

	"mvdan.cc/sh/v3/fileutil"
	"mvdan.cc/sh/v3/syntax"

	"agent-guard/rules"
)

const parseFailure = "banned-commands hook could not parse this command as bash (syntax error); refusing to run it unchecked. Fix the command and retry."

func block(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(2)
}

func refuse(format string, args ...any) {
	block(fmt.Sprintf("agent-guard "+format+"; refusing to run the command unchecked.", args...))
}

// codexSkipped は Codex では使わない判定。GREP_R は破壊を防ぐ判定ではなく
// 検索ツールの好みなので、Codex には押し付けない。
var codexSkipped = []verdict{"GREP_R"}

// bannedSkipped は Claude Code では使わない判定。Claude Code の gh api は
// .config/claude/hooks/gh-api-guard.ts が見る。
var bannedSkipped = []verdict{"GH_API_METHOD"}

type toolCall struct {
	name    string // 文字列の tool_name がなければ空
	value   string
	present bool
}

// readToolInput は payload 全体を読んでから解析する。json.Decoder は最初の値で
// 止まるので、`{...}` の後ろに NUL や別の値が続く payload を黙って受け入れて
// しまう。
func readToolInput(r io.Reader, field string) (toolCall, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return toolCall{}, fmt.Errorf("could not read the payload from stdin: %w", err)
	}
	var payload struct {
		ToolName  json.RawMessage            `json:"tool_name"`
		ToolInput map[string]json.RawMessage `json:"tool_input"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return toolCall{}, fmt.Errorf("received a malformed payload: %w", err)
	}
	var call toolCall
	// tool_name を見るのは codex モードだけなので、文字列でなくてもここでは
	// 失敗にせず、空のまま返す。
	_ = json.Unmarshal(payload.ToolName, &call.name)
	raw, ok := payload.ToolInput[field]
	if !ok || string(raw) == "null" {
		return call, nil
	}
	if err := json.Unmarshal(raw, &call.value); err != nil {
		return toolCall{}, fmt.Errorf("received a non-string tool_input.%s", field)
	}
	call.present = true
	return call, nil
}

// parse は shfmt が stdin を読むときと同じ方言を選ぶ。先頭の shebang が分かる
// 方言ならそれを、そうでなければ bash を使う。
func parse(command string) (*syntax.File, error) {
	lang := syntax.LangBash
	if err := lang.Set(fileutil.Shebang([]byte(command))); err != nil || lang == syntax.LangAuto {
		lang = syntax.LangBash
	}
	return parseAs(command, lang)
}

func commandVerdicts(command string) ([]verdict, error) {
	file, err := parse(command)
	if err != nil {
		return nil, err
	}
	return analyze(file), nil
}

func parseAs(command string, lang syntax.LangVariant) (*syntax.File, error) {
	parser := syntax.NewParser(syntax.KeepComments(true), syntax.Variant(lang))
	return parser.Parse(strings.NewReader(command+"\n"), "")
}

// checkBanned はブロックするならその理由を、通すなら "" を返す。skip に挙げた
// 判定は飛ばし、残りの先頭を使う。
func checkBanned(command string, ruleSet []rules.Rule, skip ...verdict) string {
	verdicts, err := commandVerdicts(command)
	if herdrInputCommand(command, verdicts) {
		return herdrInputMessage
	}
	if message, ok := rules.Match(command, ruleSet); ok {
		return message
	}
	if err != nil {
		return parseFailure
	}
	for _, v := range verdicts {
		if !slices.Contains(skip, v) {
			return verdictMessages[v]
		}
	}
	return ""
}

func checkCommand(command string, present bool, skip ...verdict) {
	if !present {
		refuse("received no tool_input.command string")
	}
	ruleSet, err := rules.Load()
	if err != nil {
		refuse("cannot load its rules (%v)", err)
	}
	if message := checkBanned(command, ruleSet, skip...); message != "" {
		block(message)
	}
}

func run(mode string) {
	// 端末が stdin なら Claude Code からの呼び出しではない。読むとハングする。
	if info, err := os.Stdin.Stat(); err == nil && info.Mode()&os.ModeCharDevice != 0 {
		refuse("stdin is a terminal, not a piped payload")
	}

	field := "command"
	if mode == "managed-paths" {
		field = "file_path"
	}
	call, err := readToolInput(os.Stdin, field)
	if err != nil {
		refuse("%v", err)
	}
	value, present := call.value, call.present

	switch mode {
	case "managed-paths":
		// Write/Edit 以外 (NotebookEdit など) は file_path を持たない。
		if present && value != "" && isManaged(value) {
			block(managedMessage)
		}
	case "codex":
		// matcher は ^Bash$ だが、広げたときに Bash 以外を誤って判定しないよう
		// ここでも tool_name を見る。
		if call.name == "" {
			refuse("received no tool_name string")
		}
		if call.name != "Bash" {
			return
		}
		checkCommand(value, present, codexSkipped...)
	case "banned":
		checkCommand(value, present, bannedSkipped...)
	}
}

func main() {
	if len(os.Args) != 2 || (os.Args[1] != "banned" && os.Args[1] != "codex" && os.Args[1] != "managed-paths") {
		refuse("usage: agent-guard {banned|codex|managed-paths}")
	}

	// シグナルで終わると 128+n になり、ブロックと見なされない。読み取りの途中で
	// 止まっていても、受けた時点で exit 2 にする。
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM, syscall.SIGPIPE)
	go func() {
		sig := <-signals
		refuse("received %v before reaching a verdict", sig)
	}()

	// 想定外の panic も判定に届かなかった失敗なので、ブロックに倒す。
	defer func() {
		if r := recover(); r != nil {
			refuse("failed before reaching a verdict (%v)", r)
		}
	}()

	run(os.Args[1])
}
