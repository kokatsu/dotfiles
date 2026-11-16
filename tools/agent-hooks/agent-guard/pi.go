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
// こちらは `rg gh src/` を止めないよう、unwrap が剥がした後のコマンド位置だけを見る。
// unwrap の知らないラッパーの後ろは見落とす。

import (
	"slices"
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

	args, _ := unwrap(words)
	if len(args) == 0 || args[0] != "gh" {
		return out
	}
	// xargs は -a で読むときも、入力の語を gh の後ろに足す。
	viaXargs := slices.ContainsFunc(words[:max(len(words)-len(args), 0)], func(w string) bool {
		return commandName(w) == "xargs"
	})
	rest := ghWords(args[1:], alignInfos(words, infos, args)[1:])
	path := ""
	for children, isGroup := ghGroups[path]; isGroup; children, isGroup = ghGroups[path] {
		i, ok := ghSubcommandIndex(rest)
		switch {
		case !ok, i < 0 && viaXargs:
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
	if ghRunsOther[path] {
		return append(out, "GH_SUBCOMMAND")
	}
	return out
}

// 走らせる中身を読めない操作。`gh extension exec NAME` は拡張を走らせ、
// `gh alias set` と `gh alias import` は後で走るエイリアスを作る。
var ghRunsOther = map[string]bool{"alias import": true, "alias set": true, "extension exec": true}
