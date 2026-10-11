// report-agent-session は Claude Code と Codex の SessionStart フック。
// stdin の hook payload からセッション ID を取り出し、
// `herdr pane report-agent-session` で Herdr に報告する。
//
//	report-agent-session session <claude|codex>
//
// セッションは Herdr に届いたかどうかに関係なく始まらなければならないので、
// 報告できない場合も何も出力せず exit 0 で終わる。
package main

import (
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"strconv"
	"time"
)

// 旧 Python フックのソケットのタイムアウト。ローカルの報告は 10ms ほどで返る。
// 期限を過ぎたら CommandContext の既定どおり SIGKILL する。SIGTERM を無視する
// herdr を待ってセッション開始を遅らせないため。
const timeout = 500 * time.Millisecond

type profile struct {
	// Herdr は pane のメタデータを source ごとに持つので、この文字列を変えてはならない。
	source string
	// transcript を Herdr に渡せるのは Claude Code だけ。
	reportsPath bool
	// 報告してはならない payload なら true。
	skips func(p payload, event string) bool
}

var profiles = map[string]profile{
	"claude": {
		source:      "herdr:claude",
		reportsPath: true,
		skips: func(p payload, event string) bool {
			// サブエージェントは自分の ID で動くので、pane のセッションを名乗らせない。
			return p.str("agent_id") != "" ||
				// SubagentStop は完了イベント。古い Herdr 連携はこれを継続的な
				// working に対応付けていたが、Claude の recap / away summary は
				// メインのターンが止まった後にも出すことがある。idle の pane を戻さない。
				event == "SubagentStop"
		},
	},
	"codex": {
		source: "herdr:codex",
		skips: func(p payload, event string) bool {
			// Codex は他のイベントも同じフックに流す。名前のないイベントは従来どおり
			// 受け付け、SessionStart 以外の名前だけを拒否する。
			return (event != "" && event != "SessionStart") ||
				// ephemeral なスレッドは rollout を持たないので transcript_path が null に
				// なり、Herdr が再開できるものがない。メモリ統合は pane のプロセス内で
				// ephemeral として動き、ephemeral な `codex exec` の子は HERDR_PANE_ID を
				// 継承するので、どちらも pane の本来のセッションを置き換えてしまう。
				p.str("transcript_path") == ""
		},
	},
}

// payload はキーを大文字・小文字の区別付きで引くため、struct ではなく map に読む。
// encoding/json の struct へのデコードは大文字・小文字を無視して一致させる。
type payload map[string]json.RawMessage

// str は空でない文字列の値を返す。欠落と文字列以外 (null を含む) は空文字列になる。
func (p payload) str(key string) string {
	var s string
	if json.Unmarshal(p[key], &s) != nil {
		return ""
	}
	return s
}

// reportArgs は herdr に渡す引数を返す。報告しないなら nil。
func reportArgs(agent, pane string, input []byte, seq int64) []string {
	prof, ok := profiles[agent]
	if !ok {
		return nil
	}
	// json.Decoder は最初の値で止まって後続を無視するので、全体を Unmarshal する。
	var p payload
	if json.Unmarshal(input, &p) != nil || p == nil {
		return nil
	}

	event := p.str("hook_event_name")
	if prof.skips(p, event) {
		return nil
	}
	// セッション ID はこのフックが報告する唯一の情報なので、なければ何も送らない。
	sessionID := p.str("session_id")
	if sessionID == "" {
		return nil
	}

	args := []string{
		"pane", "report-agent-session", pane,
		"--source", prof.source,
		"--agent", agent,
		// 旧フックの time.time_ns() と同じ epoch nanoseconds。再起動をまたいでも
		// 両者の順序が正しく並ぶ。
		"--seq", strconv.FormatInt(seq, 10),
		"--agent-session-id", sessionID,
	}
	if path := p.str("transcript_path"); prof.reportsPath && path != "" {
		args = append(args, "--agent-session-path", path)
	}
	if source := p.str("source"); event == "SessionStart" && source != "" {
		args = append(args, "--session-start-source", source)
	}
	return args
}

func run(args []string, stdin io.Reader) {
	if len(args) < 2 || args[0] != "session" {
		return
	}
	agent := args[1]
	if _, ok := profiles[agent]; !ok {
		return
	}
	pane := os.Getenv("HERDR_PANE_ID")
	socket := os.Getenv("HERDR_SOCKET_PATH")
	if os.Getenv("HERDR_ENV") != "1" || pane == "" || socket == "" {
		return
	}

	// Herdr は自分の store パスを HERDR_BIN_PATH で渡す。素の名前より優先すると、
	// home-manager switch がプロファイルを入れ替えている最中もフックが動く。
	// PATH の相対エントリ (`.` など) で見つかった場合、LookPath は command -v と違い
	// exec.ErrDot を返すので報告しない。
	name := os.Getenv("HERDR_BIN_PATH")
	if name == "" {
		name = "herdr"
	}
	herdr, err := exec.LookPath(name)
	if err != nil {
		return
	}

	input, err := io.ReadAll(stdin)
	if err != nil {
		return
	}
	report := reportArgs(agent, pane, input, time.Now().UnixNano())
	if report == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, herdr, report...)
	cmd.Env = []string{"HERDR_SOCKET_PATH=" + socket}
	_ = cmd.Run()
}

func main() {
	run(os.Args[1:], os.Stdin)
}
