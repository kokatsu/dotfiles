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
	"RM":             "Use gomi instead of rm",
	"EVAL":           "Refuse eval. Review the command and run it directly instead.",
	"SHRED":          "Refuse shred. Confirm intent and run manually.",
	"PKILL_F":        "Refuse pkill -f: it pattern-matches every command line, including this harness and its live servers. Kill by a recorded PID or use the tool's own stop command.",
	"KILLALL":        "Refuse killall. Kill by a recorded PID or use the tool's own stop command.",
	"MKFS":           "Refuse mkfs. Run manually if intentional.",
	"DD_DEV":         "Refuse dd writing to a device. Run manually if intentional.",
	"CHMOD_R_777":    "Refuse chmod -R 777. Use a tighter mode.",
	"CHMOD_777_ROOT": "Refuse chmod 777 /. Scope the path.",
	"GREP_R":         "Use rg instead of grep -r/-R (recursive grep). rg respects .gitignore and ~/.config/ripgrep/ripgreprc glob excludes.",
	"FORCE_PUSH":     "Refuse git push -f/--force. Use --force-with-lease or run manually.",
	"GIT_CLEAN":      "Refuse git clean -fd/-fx (destructive). Inspect untracked files first.",
	"GIT_RESET_HARD": "Refuse git reset --hard to a remote/historical ref. Confirm intent and run manually.",
	"SHALLOW":        "Refuse shallow git fetch/pull (--depth/--shallow-*) because it makes the existing repository shallow. Use a temporary shallow clone (git clone --depth), or fetch normally. --deepen/--unshallow remain allowed.",
	"GIT_IDENTITY":   "Don't set or override Git identity. ~/.config/git/config.local resolves it per directory via includeIf, and user.useConfigOnly makes Git fail loudly where no entry matches. Ask the user instead of choosing a value.",
	"EXTDIFF":        "Add --no-ext-diff to git diff/show/log -p. The global git config sets diff.external=difft, which mangles diff output when captured as tool output; --no-ext-diff is the only reliable bypass (an empty diff.external= override errors out).",
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

var (
	pkillFull   = regexp.MustCompile(`^-[A-Za-z]*f`)
	chmodRecurs = regexp.MustCompile(`^-[a-zA-Z]*R`)
)

func commandVerdict(words []string) verdict {
	args := stripWrappers(words)
	if len(args) == 0 {
		return ""
	}

	cmd := args[0]
	rest := args[1:]

	switch {
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
	var calls [][]string

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
			words := make([]string, len(node.Args))
			for i, word := range node.Args {
				words[i] = wordText(word)
			}
			calls = append(calls, words)
		}
		if name != nil && gitIdentityVar.MatchString(name.Value) {
			verdicts = append(verdicts, "GIT_IDENTITY")
		}
		return true
	})

	// env 経由なら素の語として届く。
	for _, words := range calls {
		for _, word := range words {
			if gitIdentityAssign.MatchString(word) {
				verdicts = append(verdicts, "GIT_IDENTITY")
			}
		}
	}

	for _, words := range calls {
		if v := commandVerdict(words); v != "" {
			verdicts = append(verdicts, v)
		}
	}

	return verdicts
}
