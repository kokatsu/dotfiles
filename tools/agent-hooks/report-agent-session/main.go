// report-agent-session は Claude Code と Codex の SessionStart フック。
// stdin の hook payload からセッション ID を取り出し、
// `herdr pane report-agent-session` で Herdr に報告する。
// Codex では UserPromptSubmit / Stop / Interrupt フックも兼ね、ターンの状態を
// `herdr pane report-agent` で報告する。
//
//	report-agent-session session <claude|codex>
//	report-agent-session <working|idle> codex
//
// セッションもターンも Herdr に届いたかどうかに関係なく進まなければならないので、
// 報告できない場合も何も出力せず exit 0 で終わる。
package main

import (
	"context"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
)

// 旧 Python フックのソケットのタイムアウト。ローカルの報告は 10ms ほどで返る。
// pane の確認 (process-info と ps) と報告をまとめてこの期限に収める。
// 期限を過ぎたら CommandContext の既定どおり SIGKILL する。SIGTERM を無視する
// herdr を待ってセッション開始を遅らせないため。
const timeout = 500 * time.Millisecond

type profile struct {
	// Herdr は pane のメタデータを source ごとに持つので、この文字列を変えてはならない。
	source string
	// transcript を Herdr に渡せるのは Claude Code だけ。
	reportsPath bool
	// セッションを報告してはならない payload なら true。
	skips func(p payload, event string) bool
	// working / idle も報告する。
	reportsState bool
	// HERDR_PANE_ID の pane の中で動いているときだけ報告する。
	checksPane bool
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
		reportsState: true,
		// 素の codex と codex resume は共有の app-server daemon でフックを動かし、
		// フックは daemon を起動した pane の HERDR_PANE_ID を継承する。その値を信じると
		// 別の pane のセッションを上書きする。
		checksPane: true,
	},
}

// stateEvents は状態ごとに、それを報告してよいイベント。名前のないイベントは
// SessionStart と同じく受け付ける。
var stateEvents = map[string][]string{
	"working": {"UserPromptSubmit"},
	"idle":    {"Stop", "Interrupt"},
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
func reportArgs(action, agent, pane string, input []byte, seq int64) []string {
	prof, ok := profiles[agent]
	if !ok {
		return nil
	}
	events, isState := stateEvents[action]
	if isState && !prof.reportsState || !isState && action != "session" {
		return nil
	}
	// json.Decoder は最初の値で止まって後続を無視するので、全体を Unmarshal する。
	var p payload
	if json.Unmarshal(input, &p) != nil || p == nil {
		return nil
	}

	event := p.str("hook_event_name")
	// 状態の報告は transcript_path を見ない。pane のものでないスレッドの報告は、
	// Herdr が pane の現在のセッションと ID が違うものとして捨てる。
	if isState && event != "" && !slices.Contains(events, event) || !isState && prof.skips(p, event) {
		return nil
	}
	// セッションの報告ではセッション ID が唯一の情報で、状態の報告では上の判別に
	// 使われるので、なければ何も送らない。
	sessionID := p.str("session_id")
	if sessionID == "" {
		return nil
	}

	command := "report-agent-session"
	if isState {
		command = "report-agent"
	}
	args := []string{
		"pane", command, pane,
		"--source", prof.source,
		"--agent", agent,
		// 旧フックの time.time_ns() と同じ epoch nanoseconds。再起動をまたいでも
		// 両者の順序が正しく並ぶ。
		"--seq", strconv.FormatInt(seq, 10),
		"--agent-session-id", sessionID,
	}
	if isState {
		return append(args, "--state", action)
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
	if len(args) < 2 {
		return
	}
	action, agent := args[0], args[1]
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
	report := reportArgs(action, agent, pane, input, time.Now().UnixNano())
	if report == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	if profiles[agent].checksPane && !insidePane(ctx, herdr, socket, pane) {
		return
	}
	cmd := exec.CommandContext(ctx, herdr, report...)
	cmd.Env = []string{"HERDR_SOCKET_PATH=" + socket}
	_ = cmd.Run()
}

func main() {
	run(os.Args[1:], os.Stdin)
}

// insidePane は pane のシェルがこのプロセスの祖先にいるかを返す。
// 確かめられなければ false にして報告しない。
func insidePane(ctx context.Context, herdr, socket, pane string) bool {
	info := exec.CommandContext(ctx, herdr, "pane", "process-info", "--pane", pane)
	info.Env = []string{"HERDR_SOCKET_PATH=" + socket}
	out, err := info.Output()
	if err != nil {
		return false
	}
	var reply struct {
		Result struct {
			ProcessInfo struct {
				ShellPID int `json:"shell_pid"`
			} `json:"process_info"`
		} `json:"result"`
	}
	if json.Unmarshal(out, &reply) != nil {
		return false
	}

	ps, err := exec.LookPath("ps")
	if err != nil {
		return false
	}
	// 祖先ごとに ps を起動せず、1 回の一覧を辿る。macOS (BSD) と Linux (procps) の
	// 両方が受け付ける POSIX の書き方にする。args は空白を含むので最後に置く
	out, err = exec.CommandContext(ctx, ps, "-A", "-o", "pid=", "-o", "ppid=", "-o", "args=").Output()
	if err != nil {
		return false
	}
	table, ok := parents(out)
	return ok && descends(table, os.Getpid(), reply.Result.ProcessInfo.ShellPID)
}

type process struct {
	ppid int
	args string
}

// parents は `ps -o pid= -o ppid= -o args=` の出力を pid → 親と引数の表にする。
// 形の崩れた行が 1 つでもあれば表全体を捨てる。
func parents(out []byte) (map[int]process, bool) {
	table := map[int]process{}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if len(fields) < 2 {
			return nil, false
		}
		pid, err1 := strconv.Atoi(fields[0])
		ppid, err2 := strconv.Atoi(fields[1])
		if err1 != nil || err2 != nil {
			return nil, false
		}
		table[pid] = process{ppid, strings.Join(fields[2:], " ")}
	}
	return table, len(table) > 0
}

// appServer は共有の Codex app-server か (`codex app-server ...`) を返す。
// 名前が codex のプロセスには TUI 本体もあるので、引数まで見る。
func appServer(args string) bool {
	fields := strings.Fields(args)
	return len(fields) >= 2 && filepath.Base(fields[0]) == "codex" && fields[1] == "app-server"
}

// descends は self から親を辿って shell に着くかを返す。pid 1 はどのプロセスの
// 祖先にもなるので pane のシェルとは認めない。表の大きさを超えて辿るなら循環している。
// 途中に app-server があれば着いても認めない。共有 daemon は最初に起動した pane の
// シェルの子孫に残り、どの pane のセッションのフックもその下で動くため。
func descends(table map[int]process, self, shell int) bool {
	if shell <= 1 {
		return false
	}
	for pid, steps := self, 0; steps <= len(table); steps++ {
		if pid == shell {
			return true
		}
		proc, ok := table[pid]
		if !ok || proc.ppid == pid || appServer(proc.args) {
			return false
		}
		pid = proc.ppid
	}
	return false
}
