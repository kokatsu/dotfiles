package main

import "testing"

func TestPiGhAPIFlagsBeforeSubcommand(t *testing.T) {
	for _, command := range []string{
		"gh -X DELETE api repos/o/r",
		"gh --method DELETE api repos/o/r",
		"gh --method=DELETE api repos/o/r",
		"gh --hostname github.com api -X DELETE repos/o/r",
		"gh -X POST api repos/o/r/issues -f title=x",
		"/usr/bin/gh -X DELETE api repos/o/r",
		"env gh -X DELETE api repos/o/r",
		"gh -X GET api repos/o/r",
		"P=p; gh -X DELETE a${P}i repos/o/r",
		`gh -X DELETE "$S" repos/o/r`,
		"gh -R $R repos/o/r",
		"gh -- api -X DELETE repos/o/r",
	} {
		t.Run(command, func(t *testing.T) {
			file, err := parse(command)
			if err != nil {
				t.Fatal(err)
			}
			decision, ok := ghAPIDecide(file, true)
			if !ok || decision.decision == "allow" {
				t.Fatalf("unchecked flag placement should be blocked, got %+v, present=%v", decision, ok)
			}
			if _, ok := ghAPIDecide(file, false); ok {
				t.Fatal("Claude should retain its fallback to normal approval")
			}
		})
	}
	for _, command := range []string{
		"gh api -X GET repos/o/r",
		"rg api src/",
		"gh issue view api",
		"gh --version",
		"gh -R o/r issue list --search api",
		"gh --repo o/r search issues api",
		"gh --repo=o/r issue view api",
		`gh -R "$REPO" issue list`,
	} {
		t.Run(command, func(t *testing.T) {
			file, err := parse(command)
			if err != nil {
				t.Fatal(err)
			}
			if decision, ok := ghAPIDecide(file, true); ok && decision.decision != "allow" {
				t.Fatalf("reading should remain allowed, got %+v", decision)
			}
		})
	}
}

// main の pi モードと同じく、禁止コマンドの判定と ghAPIDecide の両方を通す。
func piBlocks(t *testing.T, command string) bool {
	t.Helper()
	if checkBanned(command, loadRules(t), piSkipped...) != "" {
		return true
	}
	file, err := parse(command)
	if err != nil {
		t.Fatal(err)
	}
	decision, ok := ghAPIDecide(file, true)
	return ok && decision.decision != "allow"
}

func TestPiGhHiddenSubcommand(t *testing.T) {
	for _, command := range []string{
		"nohup gh -X DELETE api repos/o/r",
		"timeout 5 gh -X DELETE api repos/o/r",
		"xargs gh -X DELETE api r",
		"/usr/bin/env gh -X DELETE api repos/o/r",
		"ionice gh -X DELETE api repos/o/r",
		"echo gh -X DELETE api r",
		"nohup gh -R $R d",
		"sh -c 'gh -X DELETE api repos/o/r'",
		`sh -c 'gh -X DELETE a"pi" repos/o/r'`,
		`sh -c 'g"h" -X DELETE api repos/o/r'`,
		"sh -c 'gh -X DELETE \\\napi repos/o/r'",
		`find . -exec gh -X DELETE api r \;`,
		"gh co 1",
		"gh -R o/r co 1",
		"nohup gh co 1",
		"sh -c 'gh stack'",
		"gh extension exec stack",
		"gh ext exec stack",
		"echo d | xargs gh",
		`gh "$SUB" x`,
		"xargs -a f gh",
		"env -S 'gh d'",
		"gh alias set d 'api -X DELETE repos/o/r'",
		"gh alias import f",
		`sh -c 'gh a"pi" -X DELETE repos/o/r'`,
		`sh -c 'g"h" api -X DELETE repos/o/r'`,
		"sh <<'EOF'\ngh api -X DELETE repos/o/r\nEOF",
		"sh -c 'gh api -X GET repos/o/r'",
		"gh issue mine",
		"gh issue -R o/r mine",
		"nohup gh issue mine",
		"sh -c 'gh issue mine'",
		"gh repo deploy-key x",
		"gh issue artifact mine",
		`gh pr "$X"`,
		`gh "" co 1`,
		`gh "" issue mine`,
		"gh environment x",
		"xargs gh issue",
		"gh codespace ports forward 80:80",
		"gh repo delete o/r --yes",
		"gh release delete v1 -y",
		"gh pr merge 1",
		"gh pr create --fill",
		"gh issue comment 1 -b x",
		"gh -R o/r pr merge 1",
		"nohup gh pr merge 1",
		"sh -c 'gh pr merge 1'",
		"gh repo sync",
		"gh issue develop --list 1",
		"gh config get oauth_token",
		"gh auth token",
		"gh auth status -t",
		"gh auth status",
		"gh copilot",
		"gh agent-task list",
		"gh extension install o/gh-x",
		"gh workflow run ci.yml",
		"git push",
		"git push origin main",
		"git -C . push --delete origin b",
		"sh -c 'git push'",
		"nix develop -c git push",
		"nix-shell -p git --run 'git push'",
		"git po",
		"git -c alias.publish=push publish origin main",
		"git -c alias.x='!git push' x",
		"git -c alias.whatchanged=push whatchanged origin main",
		"git --attr-source status push origin main",
		"git subtree push --prefix d origin b",
		"git send-pack origin main",
		"git credential fill",
		"git lg",
		"git lfs push origin main",
		`git "$SUB"`,
		`S=x; git -c alias.statusx=push "status${S}" origin main`,
		`git -c$V status`,
		`git $OPTS status`,
		`env -S "git ${S}" x`,
		"echo push | xargs git",
		"xargs -a /tmp/args git",
		"echo push | xargs -I status git status origin main",
		"echo merge | xargs -I list gh pr list",
		"echo a | xargs git add",
		"xargs -a f gh pr list",
		"echo push | env -S 'xargs -I status git status origin main'",
		"echo merge | env -S 'xargs -I list gh pr list'",
		"nohup xargs gh pr list",
		"nohup git po",
		"sh -c 'git po'",
		`find . -exec git po \;`,
	} {
		t.Run(command, func(t *testing.T) {
			if !piBlocks(t, command) {
				t.Fatal("should be blocked in pi mode")
			}
			for _, skip := range [][]verdict{bannedSkipped, codexSkipped} {
				message := checkBanned(command, loadRules(t), skip...)
				for _, v := range []verdict{"GH_FLAGS_API", "GH_SUBCOMMAND", "GH_AUTH", "GH_WRITE", "GH_API_SCRIPT", "GIT_PUSH", "GIT_SUBCOMMAND"} {
					if message == verdictMessages[v] {
						t.Fatalf("Claude and Codex modes should not see %s", v)
					}
				}
			}
		})
	}
	for _, command := range []string{
		"gh api -X GET repos/o/r",
		"gh pr checkout 1",
		"gh -R o/r issue list",
		"nohup gh -R o/r issue list",
		"gh --version",
		"gh extension list",
		"gh alias list",
		"gh cs list",
		"gh issue ls",
		"gh pr co 1",
		"gh issue view mine",
		"gh issue --help",
		"gh ext list",
		"gh repo deploy-key list",
		"gh help environment",
		"gh environment",
		"rg gh src/",
		`rg gh "$dir"`,
		"echo gh -R o/r issue list",
		`gh issue view "$N"`,
		"gh pr view 1 --json title",
		"gh pr diff 1",
		"gh pr checks 1",
		"gh repo clone o/r",
		"gh release download v1",
		"gh run view 1 --log",
		"gh search prs foo",
		"gh workflow list",
		"gh config list",
		"gh repo view",
		"git fetch",
		"git status",
		"git diff --cached",
		"git -C . log -1",
		"git --version",
		"git commit -m x",
		"git config alias.p push",
		`git -C "$D" status`,
		`git commit -m "$MSG"`,
	} {
		t.Run(command, func(t *testing.T) {
			if piBlocks(t, command) {
				t.Fatal("should be allowed in pi mode")
			}
		})
	}
}
