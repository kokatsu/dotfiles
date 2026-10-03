// claude-bash-guard は Claude Code と Codex の PreToolUse (Bash) フック。
// stdin で hook payload を受け取り、ブロックするなら理由を stderr に出して
// exit 2 で終わる。
//
//	claude-bash-guard banned      Claude Code 用。Herdr 入力ガードと禁止コマンド
//	claude-bash-guard herdr-peer  Codex 用。Herdr 入力ガードだけ
//
// どちらもガードなので、判定に届かなかった失敗はすべて exit 2 にする。
// Claude Code と Codex は exit 2 だけをブロックとして扱い、それ以外の失敗では
// コマンドを通してしまう。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"mvdan.cc/sh/v3/fileutil"
	"mvdan.cc/sh/v3/syntax"

	"claude-bash-guard/rules"
)

const parseFailure = "banned-commands hook could not parse this command as bash (syntax error); refusing to run it unchecked. Fix the command and retry."

func block(message string) {
	fmt.Fprintln(os.Stderr, message)
	os.Exit(2)
}

func refuse(format string, args ...any) {
	block(fmt.Sprintf("bash guard "+format+"; refusing to run the command unchecked.", args...))
}

// readCommand は payload 全体を読んでから解析する。json.Decoder は最初の値で
// 止まるので、`{...}` の後ろに NUL や別の値が続く payload を黙って受け入れて
// しまう。
func readCommand(r io.Reader) (command string, present bool, err error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return "", false, fmt.Errorf("could not read the payload from stdin: %w", err)
	}
	var payload struct {
		ToolInput *struct {
			Command json.RawMessage `json:"command"`
		} `json:"tool_input"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return "", false, fmt.Errorf("received a malformed payload: %w", err)
	}
	if payload.ToolInput == nil || payload.ToolInput.Command == nil ||
		string(payload.ToolInput.Command) == "null" {
		return "", false, nil
	}
	if err := json.Unmarshal(payload.ToolInput.Command, &command); err != nil {
		return "", false, fmt.Errorf("received a non-string tool_input.command")
	}
	return command, true, nil
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

// checkBanned はブロックするならその理由を、通すなら "" を返す。
func checkBanned(command string, ruleSet []rules.Rule) string {
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
	if len(verdicts) > 0 {
		return verdictMessages[verdicts[0]]
	}
	return ""
}

func run(mode string) {
	// 端末が stdin なら Claude Code からの呼び出しではない。読むとハングする。
	if info, err := os.Stdin.Stat(); err == nil && info.Mode()&os.ModeCharDevice != 0 {
		refuse("stdin is a terminal, not a piped payload")
	}

	command, present, err := readCommand(os.Stdin)
	if err != nil {
		refuse("%v", err)
	}

	switch mode {
	case "herdr-peer":
		// Codex は Bash 以外の入力もこのフックに渡しうる。コマンドが無ければ
		// 見るものが無い。
		if !present {
			return
		}
		// 解析できない入力は正規表現だけで見る。Codex 側では禁止コマンドの判定を
		// しないので、解析の失敗そのものではブロックしない。
		verdicts, _ := commandVerdicts(command)
		if herdrInputCommand(command, verdicts) {
			block(herdrInputMessage)
		}
	case "banned":
		if !present {
			refuse("received no tool_input.command string")
		}
		ruleSet, err := rules.Load()
		if err != nil {
			refuse("cannot load its rules (%v)", err)
		}
		if message := checkBanned(command, ruleSet); message != "" {
			block(message)
		}
	}
}

func main() {
	if len(os.Args) != 2 || (os.Args[1] != "banned" && os.Args[1] != "herdr-peer") {
		refuse("usage: claude-bash-guard {banned|herdr-peer}")
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
