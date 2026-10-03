package main

// コマンド名に紐づく禁止規則。シェルの AST を歩いて見る。区切り文字の正規表現
// では改行・then/do・ラッパー・バッククォートを覆えないためである。
//
// 採用するのは最初の判定 1 つだけで、その順序は testdata/verdict-precedence-cases.txt
// が固定している。GIT_AUTHOR_*/GIT_COMMITTER_* 由来の 2 系統はコマンド中の位置に
// 関係なく先行し、コマンドごとの判定だけが AST の文書順で決まる。

import (
	"regexp"
	"slices"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

type verdict string

var verdictMessages = map[verdict]string{
	"RM":               "Use gomi instead of rm",
	"EVAL":             "Refuse eval. Review the command and run it directly instead.",
	"SHRED":            "Refuse shred. Confirm intent and run manually.",
	"PKILL_F":          "Refuse pkill -f: it pattern-matches every command line, including this harness and its live servers. Kill by a recorded PID or use the tool's own stop command.",
	"KILLALL":          "Refuse killall. Kill by a recorded PID or use the tool's own stop command.",
	"MKFS":             "Refuse mkfs. Run manually if intentional.",
	"DD_DEV":           "Refuse dd writing to a device. Run manually if intentional.",
	"CHMOD_R_777":      "Refuse chmod -R 777. Use a tighter mode.",
	"CHMOD_777_ROOT":   "Refuse chmod 777 /. Scope the path.",
	"GREP_R":           "Use rg instead of grep -r/-R (recursive grep). rg respects .gitignore and ~/.config/ripgrep/ripgreprc glob excludes.",
	"FORCE_PUSH":       "Refuse git push -f/--force. Use --force-with-lease or run manually.",
	"GIT_CLEAN":        "Refuse git clean -fd/-fx (destructive). Inspect untracked files first.",
	"GIT_RESET_HARD":   "Refuse git reset --hard to a remote/historical ref. Confirm intent and run manually.",
	"SHALLOW":          "Refuse shallow git fetch/pull (--depth/--shallow-*) because it makes the existing repository shallow. Use a temporary shallow clone (git clone --depth), or fetch normally. --deepen/--unshallow remain allowed.",
	"GIT_IDENTITY":     "Don't set or override Git identity. ~/.config/git/config.local resolves it per directory via includeIf, and user.useConfigOnly makes Git fail loudly where no entry matches. Ask the user instead of choosing a value.",
	"HERDR_INPUT":      herdrInputMessage,
	"FIND_DELETE":      "Refuse find -delete. Use find ... -exec gomi {} + instead, so the files stay recoverable.",
	"SHELL_C_UNPARSED": "Refuse sh -c with a command string that does not parse as shell: it cannot be checked, and the shell runs the lines before the error. Run the commands directly instead.",
	"EXTDIFF":          "Add --no-ext-diff to git diff/show/log -p. The global git config sets diff.external=difft, which mangles diff output when captured as tool output; --no-ext-diff is the only reliable bypass (an empty diff.external= override errors out).",
}

var shortOpt = regexp.MustCompile(`^-[A-Za-z0-9]`)

func isASCIIAlnum(c byte) bool {
	return 'A' <= c && c <= 'Z' || 'a' <= c && c <= 'z' || '0' <= c && c <= '9'
}

func hasFlag(args, flags []string) bool {
	return slices.ContainsFunc(args, func(a string) bool {
		return slices.ContainsFunc(flags, func(f string) bool {
			return a == f || strings.HasPrefix(a, f+"=")
		})
	})
}

var gitGlobalValueOpts = map[string]bool{
	"-C":           true,
	"-c":           true,
	"--git-dir":    true,
	"--work-tree":  true,
	"--namespace":  true,
	"--config-env": true,
}

func skipGitGlobals(args []string) []string {
	for len(args) > 0 {
		switch {
		case gitGlobalValueOpts[args[0]]:
			args = drop(args, 2)
		case strings.HasPrefix(args[0], "-"):
			args = args[1:]
		default:
			return args
		}
	}
	return args
}

// 短オプション束のフラグ文字を、最初の値を取る文字まで読む。"git clean -fed" の
// "d" は -e の付属値でありフラグではない。英数字以外も走査を止めるので、
// 付属値に記号が入っていても ("-fofoo-bar") 手前のフラグは隠せない。
func clusterFlags(cluster, argChars string) string {
	for i := 0; i < len(cluster); i++ {
		c := cluster[i]
		if strings.IndexByte(argChars, c) >= 0 || !isASCIIAlnum(c) {
			return cluster[:i]
		}
	}
	return cluster
}

// pathspec 区切りの "--" までを歩く。値を別に取るオプションの値を先に落とすので、
// 値そのものが "--" でも区切りとは読まれない ("git clean -e -- -fd")。
func gitOpts(args, valOpts []string, argChars string) []string {
	var out []string
	for len(args) > 0 {
		head := args[0]
		switch {
		case slices.Contains(valOpts, head),
			shortOpt.MatchString(head) && clusterEats(head[1:], argChars):
			out = append(out, head)
			args = drop(args, 2)
		case head == "--":
			return out
		default:
			out = append(out, head)
			args = args[1:]
		}
	}
	return out
}

// オプションの走査は "--" で止まる。"-R" という名前のファイルはフラグに見えない。
func optsBeforeDdash(args []string) []string {
	if end := slices.Index(args, "--"); end >= 0 {
		return args[:end]
	}
	return args
}

var attachedValue = regexp.MustCompile(`=` + jsDot + `*$`)

// GNU getopt_long と git parse-options は曖昧でない限り長オプションの前置を
// 受け付ける ("--rec" は --recursive)。付属した =value は比較前に落とす。
func isAbbrevOf(token, full string, minLen int) bool {
	t := token
	if loc := attachedValue.FindStringIndex(token); loc != nil {
		t = token[:loc[0]]
	}
	return len(t) >= minLen && strings.HasPrefix(full, t)
}

// --- grep ----------------------------------------------------------------

type grepCluster int

const (
	grepPlain grepCluster = iota
	grepRecursiveFlag
	grepEatsNext
)

// "--" でオプションが終わる。-e/-f (パターン) と -d/-D (動作) の値はデータなので、
// 別語でも付属でも束の末尾でも読み飛ばす。束の中でそれらより前に現れた r/R だけが
// 再帰を意味する。数字は束に残す ("-n2r" は文脈行数つきの再帰)。
func grepClusterVerdict(cluster string) grepCluster {
	for i := 0; i < len(cluster); i++ {
		switch cluster[i] {
		case 'r', 'R':
			return grepRecursiveFlag
		case 'e', 'f', 'd', 'D':
			if i == len(cluster)-1 {
				return grepEatsNext
			}
			return grepPlain
		}
	}
	return grepPlain
}

var grepClusterArg = regexp.MustCompile(`^-[A-Za-z0-9]+$`)

func grepRecursive(args []string) bool {
	for len(args) > 0 {
		head := args[0]
		switch {
		case head == "--":
			return false
		case isAbbrevOf(head, "--recursive", 5) ||
			isAbbrevOf(head, "--dereference-recursive", 5):
			return true
		case !strings.Contains(head, "=") &&
			(isAbbrevOf(head, "--regexp", 5) ||
				head == "--file" ||
				isAbbrevOf(head, "--devices", 5) ||
				isAbbrevOf(head, "--directories", 5)):
			args = drop(args, 2)
		case grepClusterArg.MatchString(head):
			switch grepClusterVerdict(head[1:]) {
			case grepRecursiveFlag:
				return true
			case grepEatsNext:
				args = drop(args, 2)
			default:
				args = args[1:]
			}
		default:
			args = args[1:]
		}
	}
	return false
}

// --- git identity ---------------------------------------------------------

// identity は ~/.config/git/config.local の includeIf が決め、合致しなければ
// user.useConfigOnly が失敗させる。リポジトリごとに設定するものは何もない。
// セクションとキーは大文字小文字を区別しない。
func isIdentityKey(token string) bool {
	t := strings.ToLower(token)
	return t == "user.email" || t == "user.name"
}

func isIdentityAssignment(token string) bool {
	t := strings.ToLower(token)
	return strings.HasPrefix(t, "user.email=") || strings.HasPrefix(t, "user.name=")
}

var configValueOpts = map[string]bool{
	"-f":        true,
	"--file":    true,
	"--blob":    true,
	"-t":        true,
	"--type":    true,
	"--default": true,
	"--comment": true,
	"--value":   true,
}

// git config の、値を別語で取るオプションを落とす。その値をキーや書き込みの印と
// 取り違えないようにする。
func configOperands(args []string) []string {
	var out []string
	for len(args) > 0 {
		switch {
		case configValueOpts[args[0]]:
			args = drop(args, 2)
		case strings.HasPrefix(args[0], "-"):
			args = args[1:]
		default:
			out = append(out, args[0])
			args = args[1:]
		}
	}
	return out
}

// 書き込みは identity キーの後ろに値があるか ("git config user.email x"、
// "git config set user.email x")、削除・追加のオプションで名指しされた場合。
// キーの後ろに何もなければ読み取り ("git config --get user.email")。
func configIdentityWrite(rest []string) bool {
	ops := configOperands(rest)
	i := slices.IndexFunc(ops, isIdentityKey)
	if i == -1 {
		return false
	}
	head := strings.ToLower(ops[0])
	return slices.Contains([]string{"set", "add", "unset", "unset-all", "replace-all"}, head) ||
		slices.ContainsFunc(rest, func(a string) bool {
			return slices.Contains([]string{"--unset", "--unset-all", "--replace-all", "--add"}, a)
		}) ||
		len(ops) > i+1
}

// git -c user.email=... と --config-env=user.email=VAR は一回の実行だけ identity を
// 変える。skipGitGlobals がオプションと値を落とす前に見る。
func gitGlobalIdentity(args []string) bool {
	for len(args) > 0 {
		head := args[0]
		lower := strings.ToLower(head)
		switch {
		case head == "-c" || head == "--config-env":
			if len(args) > 1 && isIdentityAssignment(args[1]) {
				return true
			}
			args = drop(args, 2)
		case strings.HasPrefix(lower, "-cuser.email=") || strings.HasPrefix(lower, "-cuser.name="):
			return true
		case strings.HasPrefix(head, "--config-env="):
			if isIdentityAssignment(head[len("--config-env="):]) {
				return true
			}
			args = args[1:]
		case strings.HasPrefix(head, "-"):
			args = args[1:]
		default:
			return false
		}
	}
	return false
}

// --- git サブコマンド -----------------------------------------------------

// diff/show/log の一覧は実際の git で確認した、値を「別語で」取るものだけ。
// 単独で有効なもの (-U、--unified、--pretty、--format) や = 必須のもの
// (--date、--max-count、--skip、-l) を入れてはいけない。入れると本物の "--" を
// 食べてしまう。
func valueOptsFor(sub string) ([]string, string) {
	switch sub {
	case "clean":
		return []string{"-e", "--exclude"}, "e"
	case "fetch", "pull":
		return []string{
			"--upload-pack",
			"-o",
			"--server-option",
			"--negotiation-tip",
			"--refmap",
			"-j",
			"--jobs",
			"--depth",
			"--shallow-since",
			"--shallow-exclude",
		}, "jo"
	case "push":
		return []string{"--receive-pack", "--exec", "--repo", "-o", "--push-option"}, "o"
	case "diff", "show", "log":
		return []string{
			"-G",
			"-S",
			"-O",
			"-n",
			"-L",
			"--since",
			"--until",
			"--author",
			"--committer",
			"--grep",
			"--output",
			"--rotate-to",
			"--skip-to",
			"--find-object",
			"--decorate-refs",
			"--decorate-refs-exclude",
		}, "GSOnL"
	default:
		return nil, ""
	}
}

var (
	identityFragment = regexp.MustCompile(`user\.(email|name)`)
	patchFlag        = regexp.MustCompile(`[pu]`)
)

func gitVerdict(args []string) verdict {
	if gitGlobalIdentity(args) {
		return "GIT_IDENTITY"
	}

	rest := skipGitGlobals(args)
	if len(rest) == 0 {
		return ""
	}

	sub := rest[0]
	valOpts, valChars := valueOptsFor(sub)
	// "--" の後ろは全て pathspec/refspec なので、フラグの走査は区切りの手前だけを
	// 見る。"--force" という名前のパスをフラグと読まないためと、"--no-ext-diff" と
	// いう名前のパスで外部 diff のガードを外させないためである。
	opts := gitOpts(rest[1:], valOpts, valChars)

	if sub == "push" && slices.ContainsFunc(opts, func(a string) bool {
		return a == "--force" ||
			(shortOpt.MatchString(a) && strings.Contains(clusterFlags(a[1:], "o"), "f"))
	}) {
		return "FORCE_PUSH"
	}

	if sub == "clean" {
		var letters strings.Builder
		for _, a := range opts {
			if shortOpt.MatchString(a) {
				letters.WriteString(clusterFlags(a[1:], "e"))
			}
		}
		if slices.ContainsFunc(opts, func(a string) bool { return isAbbrevOf(a, "--force", 3) }) {
			letters.WriteString("f")
		}
		l := letters.String()
		if strings.Contains(l, "f") && (strings.Contains(l, "d") || strings.Contains(l, "x")) {
			return "GIT_CLEAN"
		}
	}

	if sub == "reset" && slices.Contains(opts, "--hard") &&
		slices.ContainsFunc(opts, func(a string) bool {
			return strings.HasPrefix(a, "origin/") ||
				strings.HasPrefix(a, "upstream/") ||
				strings.HasPrefix(a, "HEAD~") ||
				strings.HasPrefix(a, "HEAD@")
		}) {
		return "GIT_RESET_HARD"
	}

	if (sub == "fetch" || sub == "pull") &&
		hasFlag(opts, []string{"--depth", "--shallow-since", "--shallow-exclude", "--update-shallow"}) {
		return "SHALLOW"
	}

	if sub == "config" && configIdentityWrite(rest[1:]) {
		return "GIT_IDENTITY"
	}

	// --author が authorship を書き換えるのは、それを記録するコマンドだけ。
	// "git log --author" は絞り込みなので通す。
	if (sub == "commit" || sub == "am") &&
		slices.ContainsFunc(opts, func(a string) bool { return isAbbrevOf(a, "--author", 4) }) {
		return "GIT_IDENTITY"
	}

	// これらはコマンドを 1 つの文字列で受け取る。parser は 1 語として扱うので、
	// 下の identity 検査までは届かない。文字列の中の断片で見る。ここに identity の
	// キーを渡す正当な用途はない。
	if (sub == "rebase" || sub == "filter-branch" || sub == "bisect") &&
		slices.ContainsFunc(opts, func(a string) bool {
			return strings.Contains(a, "--author") || identityFragment.MatchString(strings.ToLower(a))
		}) {
		return "GIT_IDENTITY"
	}

	if (sub == "diff" || sub == "show" ||
		(sub == "log" && slices.ContainsFunc(opts, func(a string) bool {
			return a == "--patch" ||
				(shortOpt.MatchString(a) && patchFlag.MatchString(clusterFlags(a[1:], "GSOnL")))
		}))) &&
		!slices.Contains(opts, "--no-ext-diff") {
		return "EXTDIFF"
	}

	return ""
}

// --- コマンド単位の判定 ---------------------------------------------------

func shellVariant(shell string) (syntax.LangVariant, bool) {
	switch shell {
	case "sh", "bash", "dash", "ash":
		return syntax.LangBash, true
	case "zsh":
		return syntax.LangZsh, true
	case "ksh", "mksh":
		return syntax.LangMirBSDKorn, true
	}
	return 0, false
}

// シェルの引数から -c に渡した文字列を探す。-c が無ければ最初のオペランドは
// スクリプトのファイルで、そこから先はその引数なので見ない。-o/-O は値を取り、
// 束 ("-eo pipefail") の末尾にあっても次の語を食べる。
func shellCommandString(args []string) (int, bool) {
	hasC := false
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--" || a == "-":
			if hasC && i+1 < len(args) {
				return i + 1, true
			}
			return 0, false
		case a == "--rcfile" || a == "--init-file":
			i++
		case strings.HasPrefix(a, "--"):
		case len(a) > 1 && (a[0] == '-' || a[0] == '+'):
			if a[0] == '-' && strings.Contains(a[1:], "c") {
				hasC = true
			}
			if last := a[len(a)-1]; last == 'o' || last == 'O' {
				i++
			}
		default:
			if hasC {
				return i, true
			}
			return 0, false
		}
	}
	return 0, false
}

// ラッパーを剥がした後の引数は元の語の末尾と並びが揃うので、末尾から数えて
// scriptText を対応づける。env -S が分割して作った語は元の語と一致しないので、
// 分割後の文字列をそのまま使う。
func alignScripts(words, scripts, rest []string) []string {
	out := make([]string, len(rest))
	for i, arg := range rest {
		out[i] = arg
		if k := len(words) - len(rest) + i; k >= 0 && words[k] == arg {
			out[i] = scripts[k]
		}
	}
	return out
}

type embedded struct{ words, scripts []string }

// 実行するコマンドの範囲を start から終端の手前まで取り出す。find は ";" か
// "{} +" で、fd は ";" で終わり、終端が無ければ末尾まで。返す添字は終端の位置。
func embeddedSpan(cmd string, rest, scripts []string, start int) (embedded, int) {
	end := start
	for end < len(rest) && rest[end] != ";" &&
		!(cmd == "find" && rest[end] == "+" && end > start && rest[end-1] == "{}") {
		end++
	}
	return embedded{rest[start:end], scripts[start:end]}, end
}

// 値を 1 つ取る find の条件とオプション。値が "-exec" や "-delete" でも
// アクションと読まないよう読み飛ばす。-newerXY と -anewer などは名前の形で見る。
var findValueOpts = map[string]bool{
	"-name": true, "-iname": true, "-path": true, "-ipath": true,
	"-wholename": true, "-iwholename": true, "-regex": true, "-iregex": true,
	"-lname": true, "-ilname": true, "-type": true, "-xtype": true,
	"-user": true, "-group": true, "-uid": true, "-gid": true,
	"-perm": true, "-size": true, "-mtime": true, "-atime": true,
	"-ctime": true, "-Btime": true, "-mmin": true, "-amin": true,
	"-cmin": true, "-Bmin": true, "-used": true, "-links": true,
	"-inum": true, "-samefile": true, "-maxdepth": true, "-mindepth": true,
	"-fstype": true, "-context": true, "-fprint": true, "-fprint0": true,
	"-fls": true, "-printf": true, "-regextype": true, "-files0-from": true,
	"-flags": true, "-D": true,
}

// find の式を走査し、-exec/-execdir/-ok/-okdir が実行するコマンドと、
// アクションとしての -delete があるかを返す。条件の値と、実行するコマンドの
// 引数は式として読まない。
func findActions(rest, scripts []string) ([]embedded, bool) {
	var subs []embedded
	deletes := false
	for i := 0; i < len(rest); i++ {
		a := rest[i]
		switch {
		case a == "-exec" || a == "-execdir" || a == "-ok" || a == "-okdir":
			var sub embedded
			sub, i = embeddedSpan("find", rest, scripts, i+1)
			subs = append(subs, sub)
		case a == "-delete":
			deletes = true
		case a == "-fprintf":
			i += 2
		case findValueOpts[a] || strings.HasPrefix(a, "-newer") || strings.HasSuffix(a, "newer"):
			i++
		}
	}
	return subs, deletes
}

// fd の短オプションのうち値を取るもの。束の中でこれより後ろは値になる。
const fdValueShort = "dEteSojcC"

// fd の -x/--exec/-X/--exec-batch が実行するコマンドを返す。値が付属した形
// (--exec=CMD、-xCMD) では付属した 1 語だけがコマンドで、後ろの語は fd の引数に
// 戻る。"--" の後ろはパターンとパスなので、オプションとして読まない。
func fdCommands(rest, scripts []string) []embedded {
	var subs []embedded
	oneWord := func(cmd string) {
		subs = append(subs, embedded{[]string{cmd}, []string{cmd}})
	}
	for i := 0; i < len(rest); i++ {
		a := rest[i]
		switch {
		case a == "--":
			return subs
		case a == "-x" || a == "--exec" || a == "-X" || a == "--exec-batch":
			var sub embedded
			sub, i = embeddedSpan("fd", rest, scripts, i+1)
			subs = append(subs, sub)
		case strings.HasPrefix(a, "--exec=") || strings.HasPrefix(a, "--exec-batch="):
			oneWord(a[strings.Index(a, "=")+1:])
		case strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--"):
			for j := 1; j < len(a); j++ {
				if strings.IndexByte(fdValueShort, a[j]) >= 0 {
					break
				}
				if a[j] == 'x' || a[j] == 'X' {
					if j+1 < len(a) {
						oneWord(a[j+1:])
					} else {
						var sub embedded
						sub, i = embeddedSpan("fd", rest, scripts, i+1)
						subs = append(subs, sub)
					}
					break
				}
			}
		}
	}
	return subs
}

func isHerdrInput(rest []string) bool {
	if len(rest) < 2 {
		return false
	}
	switch rest[0] {
	case "agent":
		return rest[1] == "prompt" || rest[1] == "send-keys"
	case "pane":
		return rest[1] == "send-text" || rest[1] == "send-keys" || rest[1] == "run"
	}
	return false
}

var (
	pkillFull   = regexp.MustCompile(`^-[A-Za-z]*f`)
	chmodRecurs = regexp.MustCompile(`^-[a-zA-Z]*R`)
)

// scripts は words と同じ並びの、bash が実際に渡す文字列 (scriptText)。
//
// 判定は出る順の並びで返す。入れ子 (sh -c、find -exec、fd -x) の中の判定を
// 先頭 1 つに絞ると、後ろにある HERDR_INPUT が herdr-peer モードから見えなくなる。
func commandVerdict(words, scripts []string) []verdict {
	args := stripWrappers(words)
	if len(args) == 0 {
		return nil
	}

	cmd := args[0]
	rest := args[1:]
	restScripts := alignScripts(words, scripts, rest)

	// 文字列で受け取ったコマンドを解析し直して、同じ判定にかける。
	if lang, ok := shellVariant(cmd); ok {
		if i, ok := shellCommandString(rest); ok {
			file, err := parseAs(restScripts[i], lang)
			if err != nil {
				return []verdict{"SHELL_C_UNPARSED"}
			}
			return analyze(file)
		}
		return nil
	}

	// 引数として受け取ったコマンドを同じ判定にかける。
	if cmd == "find" || cmd == "fd" {
		var subs []embedded
		deletes := false
		if cmd == "find" {
			subs, deletes = findActions(rest, restScripts)
		} else {
			subs = fdCommands(rest, restScripts)
		}
		var out []verdict
		for _, sub := range subs {
			out = append(out, commandVerdict(sub.words, sub.scripts)...)
		}
		if deletes {
			out = append(out, "FIND_DELETE")
		}
		return out
	}

	if v := singleVerdict(cmd, rest); v != "" {
		return []verdict{v}
	}
	return nil
}

func singleVerdict(cmd string, rest []string) verdict {
	switch {
	case cmd == "herdr" && isHerdrInput(rest):
		return "HERDR_INPUT"
	case cmd == "rm":
		return "RM"
	case cmd == "eval":
		return "EVAL"
	case cmd == "shred":
		return "SHRED"
	case cmd == "pkill" && slices.ContainsFunc(optsBeforeDdash(rest), func(a string) bool {
		return a == "--full" || pkillFull.MatchString(a)
	}):
		return "PKILL_F"
	case cmd == "killall":
		return "KILLALL"
	case strings.HasPrefix(cmd, "mkfs."):
		return "MKFS"
	case cmd == "dd" && slices.ContainsFunc(rest, func(a string) bool { return strings.HasPrefix(a, "of=/dev/") }):
		return "DD_DEV"
	case cmd == "chmod":
		// --reference では数値モードの引数が存在しない。"777" はファイル名
		// (参照元か対象パス) である。
		if slices.ContainsFunc(optsBeforeDdash(rest), func(a string) bool { return isAbbrevOf(a, "--reference", 5) }) {
			return ""
		}
		if !slices.Contains(rest, "777") && !slices.Contains(rest, "0777") {
			return ""
		}
		if slices.ContainsFunc(optsBeforeDdash(rest), func(a string) bool {
			return chmodRecurs.MatchString(a) || isAbbrevOf(a, "--recursive", 5)
		}) {
			return "CHMOD_R_777"
		}
		if slices.Contains(rest, "/") {
			return "CHMOD_777_ROOT"
		}
		return ""
	case (cmd == "grep" || cmd == "egrep" || cmd == "fgrep") && grepRecursive(rest):
		return "GREP_R"
	case cmd == "git":
		return gitVerdict(rest)
	}
	return ""
}

// --- AST 全体の走査 -------------------------------------------------------

var (
	gitIdentityVar    = regexp.MustCompile(`^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)$`)
	gitIdentityAssign = regexp.MustCompile(`^GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)=`)
)

// 判定を出る順に返す。採用するのは先頭 1 つだけだが、順序は
// testdata/verdict-precedence-cases.txt が固定している契約なので、途中で
// 打ち切らずに並びとして組み立てる。
func analyze(file *syntax.File) []verdict {
	var verdicts []verdict
	type call struct{ words, scripts []string }
	var calls []call

	syntax.Walk(file, func(node syntax.Node) bool {
		// GIT_AUTHOR_* / GIT_COMMITTER_* は config を触らずに identity を変える。
		// 代入の前置でも export でも Assign になる。for の変数と関数名も同じ
		// 名前の欄を持つので、取りこぼさないよう同じく見る。
		var name *syntax.Lit
		switch node := node.(type) {
		case *syntax.Assign:
			name = node.Name
		case *syntax.WordIter:
			name = node.Name
		case *syntax.FuncDecl:
			name = node.Name
		case *syntax.CallExpr:
			c := call{make([]string, len(node.Args)), make([]string, len(node.Args))}
			for i, word := range node.Args {
				c.words[i] = wordText(word)
				c.scripts[i] = scriptText(word)
			}
			calls = append(calls, c)
		}
		if name != nil && gitIdentityVar.MatchString(name.Value) {
			verdicts = append(verdicts, "GIT_IDENTITY")
		}
		return true
	})

	// env 経由なら素の語として届く。
	for _, c := range calls {
		for _, word := range c.words {
			if gitIdentityAssign.MatchString(word) {
				verdicts = append(verdicts, "GIT_IDENTITY")
			}
		}
	}

	for _, c := range calls {
		verdicts = append(verdicts, commandVerdict(c.words, c.scripts)...)
	}

	return verdicts
}
