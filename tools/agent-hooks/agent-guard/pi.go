package main

// Pi だけの判定。Pi は確認を求められないので、ghAPIDecide が gh api の読み取り
// 以外を止める。ここには ghAPIDecide が gh api と読めない形を置く。banned の判定
// なので、sh -c の文字列や find -exec の範囲にも届く。
//
// GH_FLAGS_API: api の前に置いたフラグ (`gh -X DELETE api r`)。ghAPIDecide は
// コマンド位置の gh しか読まず、剥がせるラッパーの一覧は閉じないので、
// ghAPIVerdict と同じく位置を問わず字面の gh を読む。`echo gh -X DELETE api` も止まる。
//
// GH_SUBCOMMAND: エイリアスと拡張の呼び出しと定義。展開後に何が走るかを読めない。
// GH_AUTH と GH_WRITE: 認証情報に触れる操作と、ghReadOnly に無い操作。
// これらは `rg gh src/` を止めないよう、unwrap が剥がした後のコマンド位置だけを見る。
// unwrap の知らないラッパーの後ろは見落とす。
//
// GIT_PUSH と GIT_SUBCOMMAND: remote へ送る git のコマンドと、alias や外部
// コマンドの呼び出し。止めるのはこれらの直接の呼び出しだけで、git 経由の書き込み
// 全般ではない。文字列で渡すコマンド (rebase --exec、submodule foreach) や、
// 設定した helper と hook を介して走るものは読まない。

import (
	"strings"
)

// gh がエイリアスを足せるグループと、その子の名前 (別名を含む) から正規名への表。
// gh はエイリアスを実行できないコマンドの直下にしか置かないので、グループを辿る間の
// 語がすべてここにあれば、エイリアスは割り込めない。gh 2.104.0 で作った。子は
// 空の GH_CONFIG_DIR と XDG_DATA_HOME で取った `gh help reference` の見出しと
// Aliases の欄 (既定のエイリアス co を除く) に、`gh help` のヘルプトピックを足した
// もの。グループは、各コマンドパスに `gh alias set '<パス> zzz' 'issue list'` が
// 通るかで決めた。gh を更新して増えたコマンドは、ここに足すまで止まる。
var ghGroups = map[string]map[string]string{
	"": {
		"accessibility": "accessibility", "actions": "actions", "agent": "agent-task",
		"agent-task": "agent-task", "agent-tasks": "agent-task", "agents": "agent-task",
		"alias": "alias", "api": "api", "at": "attestation", "attestation": "attestation",
		"auth": "auth", "browse": "browse", "cache": "cache", "codespace": "codespace",
		"completion": "completion", "config": "config", "copilot": "copilot", "cs": "codespace",
		"discussion": "discussion", "environment": "environment", "exit-codes": "exit-codes",
		"ext": "extension", "extension": "extension", "extensions": "extension",
		"formatting": "formatting", "gist": "gist", "gpg-key": "gpg-key", "help": "help",
		"issue": "issue", "label": "label", "licenses": "licenses", "mintty": "mintty",
		"org": "org", "pr": "pr", "preview": "preview", "project": "project",
		"reference": "reference", "release": "release", "repo": "repo", "rs": "ruleset",
		"ruleset": "ruleset", "run": "run", "search": "search", "secret": "secret",
		"skill": "skill", "skills": "skill", "ssh-key": "ssh-key", "status": "status",
		"telemetry": "telemetry", "variable": "variable", "version": "version",
		"workflow": "workflow",
	},
	"actions": {},
	"alias": {
		"delete": "delete", "import": "import", "list": "list", "ls": "list", "set": "set",
	},
	"attestation": {
		"download": "download", "trusted-root": "trusted-root", "verify": "verify",
	},
	"auth": {
		"login": "login", "logout": "logout", "refresh": "refresh", "setup-git": "setup-git",
		"status": "status", "switch": "switch", "token": "token",
	},
	"cache": {
		"delete": "delete", "list": "list", "ls": "list",
	},
	"codespace": {
		"code": "code", "cp": "cp", "create": "create", "delete": "delete", "edit": "edit",
		"jupyter": "jupyter", "list": "list", "logs": "logs", "ls": "list", "ports": "ports",
		"rebuild": "rebuild", "ssh": "ssh", "stop": "stop", "view": "view",
	},
	"config": {
		"clear-cache": "clear-cache", "get": "get", "list": "list", "ls": "list", "set": "set",
	},
	"discussion": {
		"comment": "comment", "create": "create", "edit": "edit", "list": "list", "ls": "list",
		"view": "view",
	},
	"environment": {},
	"exit-codes":  {},
	"extension": {
		"browse": "browse", "create": "create", "exec": "exec", "install": "install",
		"list": "list", "ls": "list", "remove": "remove", "search": "search",
		"uninstall": "remove", "upgrade": "upgrade",
	},
	"formatting": {},
	"gist": {
		"clone": "clone", "create": "create", "delete": "delete", "edit": "edit", "list": "list",
		"ls": "list", "new": "create", "rename": "rename", "view": "view",
	},
	"gpg-key": {
		"add": "add", "delete": "delete", "list": "list", "ls": "list",
	},
	"issue": {
		"artifact": "artifact", "close": "close", "comment": "comment", "create": "create",
		"delete": "delete", "develop": "develop", "edit": "edit", "list": "list", "lock": "lock",
		"ls": "list", "new": "create", "pin": "pin", "reopen": "reopen", "status": "status",
		"transfer": "transfer", "unlock": "unlock", "unpin": "unpin", "view": "view",
	},
	"issue artifact": {
		"create": "create", "delete": "delete", "download": "download", "edit": "edit",
		"list": "list", "ls": "list", "new": "create", "view": "view",
	},
	"label": {
		"clone": "clone", "create": "create", "delete": "delete", "edit": "edit", "list": "list",
		"ls": "list",
	},
	"mintty": {},
	"org": {
		"list": "list", "ls": "list",
	},
	"pr": {
		"checkout": "checkout", "checks": "checks", "close": "close", "co": "checkout",
		"comment": "comment", "create": "create", "diff": "diff", "edit": "edit", "list": "list",
		"lock": "lock", "ls": "list", "merge": "merge", "new": "create", "ready": "ready",
		"reopen": "reopen", "revert": "revert", "review": "review", "status": "status",
		"unlock": "unlock", "update-branch": "update-branch", "view": "view",
	},
	"preview": {
		"prompter": "prompter",
	},
	"project": {
		"close": "close", "copy": "copy", "create": "create", "delete": "delete", "edit": "edit",
		"field-create": "field-create", "field-delete": "field-delete",
		"field-list": "field-list", "item-add": "item-add", "item-archive": "item-archive",
		"item-create": "item-create", "item-delete": "item-delete", "item-edit": "item-edit",
		"item-list": "item-list", "link": "link", "list": "list", "ls": "list",
		"mark-template": "mark-template", "unlink": "unlink", "view": "view",
	},
	"reference": {},
	"release": {
		"create": "create", "delete": "delete", "delete-asset": "delete-asset",
		"download": "download", "edit": "edit", "list": "list", "ls": "list", "new": "create",
		"upload": "upload", "verify": "verify", "verify-asset": "verify-asset", "view": "view",
	},
	"repo": {
		"archive": "archive", "autolink": "autolink", "clone": "clone", "create": "create",
		"delete": "delete", "deploy-key": "deploy-key", "edit": "edit", "fork": "fork",
		"gitignore": "gitignore", "license": "license", "list": "list", "ls": "list",
		"new": "create", "read-dir": "read-dir", "read-file": "read-file", "rename": "rename",
		"set-default": "set-default", "sync": "sync", "unarchive": "unarchive", "view": "view",
	},
	"repo autolink": {
		"create": "create", "delete": "delete", "list": "list", "ls": "list", "new": "create",
		"view": "view",
	},
	"repo deploy-key": {
		"add": "add", "delete": "delete", "list": "list", "ls": "list",
	},
	"repo gitignore": {
		"list": "list", "ls": "list", "view": "view",
	},
	"repo license": {
		"list": "list", "ls": "list", "view": "view",
	},
	"ruleset": {
		"check": "check", "list": "list", "ls": "list", "view": "view",
	},
	"run": {
		"cancel": "cancel", "delete": "delete", "download": "download", "list": "list",
		"ls": "list", "rerun": "rerun", "view": "view", "watch": "watch",
	},
	"search": {
		"code": "code", "commits": "commits", "issues": "issues", "prs": "prs", "repos": "repos",
	},
	"secret": {
		"delete": "delete", "list": "list", "ls": "list", "remove": "delete", "set": "set",
	},
	"skill": {
		"add": "install", "install": "install", "list": "list", "ls": "list",
		"preview": "preview", "publish": "publish", "search": "search", "show": "preview",
		"update": "update",
	},
	"ssh-key": {
		"add": "add", "delete": "delete", "list": "list", "ls": "list",
	},
	"telemetry": {},
	"variable": {
		"delete": "delete", "get": "get", "list": "list", "ls": "list", "remove": "delete",
		"set": "set",
	},
	"workflow": {
		"disable": "disable", "enable": "enable", "list": "list", "ls": "list", "run": "run",
		"view": "view",
	},
}

func ghWords(texts []string, infos []wordInfo) []ghAPIWord {
	out := make([]ghAPIWord, len(texts))
	for i, text := range texts {
		if infos[i].literal && !infos[i].unsure {
			out[i].literal = &text
		}
		out[i].splittable = infos[i].splittable
	}
	return out
}

func piGhVerdicts(words []string, infos []wordInfo) []verdict {
	var out []verdict
	for i := 0; i+1 < len(words); i++ {
		if !infos[i].literal || commandName(words[i]) != "gh" ||
			!infos[i+1].literal || !strings.HasPrefix(words[i+1], "-") {
			continue
		}
		if sub, ok := ghSubcommandAfterFlags(ghWords(words[i+1:], infos[i+1:])); !ok || sub == "api" {
			out = append(out, "GH_FLAGS_API")
			break
		}
	}

	args, _, xargs := unwrap(words)
	if len(args) == 0 || args[0] != "gh" {
		return out
	}
	// xargs の後ろのコマンドは、走るときの語を読めない。入力元が -a のファイルでも
	// 入力の語を後ろに足し、-I は手前の語 (サブコマンドも含む) を入力で置き換える。
	if xargs {
		return append(out, "GH_SUBCOMMAND")
	}
	rest := ghWords(args[1:], alignInfos(words, infos, args)[1:])
	path := ""
	for children, isGroup := ghGroups[path]; isGroup; children, isGroup = ghGroups[path] {
		i, ok := ghSubcommandIndex(rest)
		switch {
		case !ok:
			return append(out, "GH_SUBCOMMAND")
		case i < 0:
			return out
		}
		name, ok := children[*rest[i].literal]
		if !ok {
			return append(out, "GH_SUBCOMMAND")
		}
		path = strings.TrimSpace(path + " " + name)
		rest = rest[i+1:]
	}
	switch {
	case ghRunsOther[path]:
		return append(out, "GH_SUBCOMMAND")
	case strings.HasPrefix(path, "auth "):
		return append(out, "GH_AUTH")
	case !ghReadOnly[path]:
		return append(out, "GH_WRITE")
	}
	return out
}

// Pi が確認なしで走らせてよい gh の操作。GitHub と gh の認証を変えず、他のコードを
// 走らせない。名前が読み取りでも外したものがある。`config get` は
// oauth_token を返しうる。`repo sync` は remote の fork を更新し、`issue develop` は
// remote にブランチを作る。`codespace ports` は visibility を変えられる。
// api は ghAPIDecide が見る。
var ghReadOnly = map[string]bool{
	"accessibility": true, "api": true, "browse": true, "completion": true, "help": true,
	"licenses": true, "status": true, "version": true,
	"alias delete": true, "alias list": true,
	"attestation download": true, "attestation trusted-root": true, "attestation verify": true,
	"cache list":     true,
	"codespace list": true, "codespace logs": true, "codespace view": true,
	"config clear-cache": true, "config list": true,
	"discussion list": true, "discussion view": true,
	"extension browse": true, "extension list": true, "extension search": true,
	"gist clone": true, "gist list": true, "gist view": true,
	"gpg-key list": true,
	"issue list":   true, "issue status": true, "issue view": true,
	"issue artifact download": true, "issue artifact list": true, "issue artifact view": true,
	"label list":  true,
	"org list":    true,
	"pr checkout": true, "pr checks": true, "pr diff": true, "pr list": true, "pr status": true,
	"pr view":            true,
	"preview prompter":   true,
	"project field-list": true, "project item-list": true, "project list": true, "project view": true,
	"release download": true, "release list": true, "release verify": true,
	"release verify-asset": true, "release view": true,
	"repo clone": true, "repo list": true, "repo read-dir": true, "repo read-file": true,
	"repo set-default": true, "repo view": true,
	"repo autolink list": true, "repo autolink view": true, "repo deploy-key list": true,
	"repo gitignore list": true, "repo gitignore view": true,
	"repo license list": true, "repo license view": true,
	"ruleset check": true, "ruleset list": true, "ruleset view": true,
	"run download": true, "run list": true, "run view": true, "run watch": true,
	"search code": true, "search commits": true, "search issues": true, "search prs": true,
	"search repos": true,
	"secret list":  true,
	"skill list":   true, "skill preview": true, "skill search": true,
	"ssh-key list": true,
	"variable get": true, "variable list": true,
	"workflow list": true, "workflow view": true,
}

// Pi が走らせてよい git のサブコマンド。git 2.56.0 の `git --list-cmds=main` から
// gitSends を除いた同梱コマンドの固定の一覧。一覧に無い名前は alias か外部コマンドで、
// 何が走るかを読めない。git を更新して増えたコマンドは、ここに足すまで止まる。
var gitCommands = wordSet(`
add am annotate apply archimport archive backfill bisect blame branch bugreport bundle
cat-file check-attr check-ignore check-mailmap check-ref-format checkout checkout--worker
checkout-index cherry cherry-pick citool clean clone column commit commit-graph
commit-tree config count-objects cvsexportcommit cvsimport cvsserver daemon describe
diagnose diff diff-files diff-index diff-pairs diff-tree difftool difftool--helper
fast-export fast-import fetch fetch-pack filter-branch fmt-merge-msg for-each-ref
for-each-repo format-patch format-rev fsck fsck-objects fsmonitor--daemon gc
get-tar-commit-id grep gui--askpass gui--askyesno hash-object help history hook
http-backend http-fetch index-pack init init-db instaweb interpret-trailers last-modified
log ls-files ls-remote ls-tree mailinfo mailsplit maintenance merge merge-base merge-file
merge-index merge-octopus merge-one-file merge-ours merge-recursive merge-recursive-ours
merge-recursive-theirs merge-resolve merge-subtree merge-tree mergetool mktag mktree
multi-pack-index mv name-rev notes p4 pack-objects pack-redundant pack-refs patch-id
pickaxe prune prune-packed pull quiltimport range-diff read-tree rebase receive-pack
reflog refs remote repack replace replay repo request-pull rerere reset restore rev-list
rev-parse revert rm sh-i18n--envsubst shell shortlog show show-branch show-index show-ref
sparse-checkout stage stash status stripspace submodule submodule--helper switch
symbolic-ref tag unpack-file unpack-objects update-index update-ref update-server-info
upload-archive upload-archive--writer upload-pack url-parse var verify-commit verify-pack
verify-tag version web--browse whatchanged worktree write-tree
`)

// 手元の内容を remote やメールで送るか、認証情報を読む git の同梱コマンド。
var gitSends = wordSet(`
credential credential-cache credential-cache--daemon credential-netrc credential-store
http-push imap-send push remote-ext remote-fd remote-ftp remote-ftps remote-http
remote-https send-email send-pack subtree
`)

// サブコマンドは展開を含まない語でなければ読めない。`"status${S}"` は字面では
// status でも、走るときは alias の statusS になる。その手前のオプションも、分割
// される展開なら `-c alias.x=push x` を割り込ませられる。
func piGitVerdict(words []string, infos []wordInfo) verdict {
	args, _, xargs := unwrap(words)
	if len(args) == 0 || args[0] != "git" {
		return ""
	}
	// piGhVerdicts と同じく、xargs の後ろの語は読めない。
	if xargs {
		return "GIT_SUBCOMMAND"
	}
	rest := skipGitGlobals(args[1:])
	argInfos := alignInfos(words, infos, args)
	sub := len(args) - len(rest)
	for _, info := range argInfos[1:sub] {
		if info.splittable || info.unsure {
			return "GIT_SUBCOMMAND"
		}
	}
	if len(rest) == 0 {
		return ""
	}
	if !argInfos[sub].literal || argInfos[sub].unsure {
		return "GIT_SUBCOMMAND"
	}
	switch {
	case gitSends[rest[0]]:
		return "GIT_PUSH"
	case !gitCommands[rest[0]]:
		return "GIT_SUBCOMMAND"
	}
	return ""
}

func wordSet(words string) map[string]bool {
	set := map[string]bool{}
	for _, word := range strings.Fields(words) {
		set[word] = true
	}
	return set
}

// 走らせる中身を読めない操作。`gh extension exec NAME` は拡張を走らせ、
// `gh alias set` と `gh alias import` は後で走るエイリアスを作る。
var ghRunsOther = map[string]bool{"alias import": true, "alias set": true, "extension exec": true}
