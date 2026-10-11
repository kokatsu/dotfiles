package main

import (
	"os"
	"path/filepath"
	"strings"
)

const managedMessage = "Do not edit Home Manager managed paths directly. Edit the corresponding source in the repository's nix/home/ or .config/ directory instead."

// isManaged は、パスの全要素の symlink を解いた先が /nix/store の配下かを返す。
// ~/.config/claude/skills -> /nix/store/... のように途中のディレクトリが symlink
// でも捕まえる。mkOutOfStoreSymlink の先はリポジトリへ解決されるので通る。
func isManaged(path string) bool {
	resolved, ok := resolve(path, 0)
	return ok && strings.HasPrefix(resolved, "/nix/store/")
}

// resolve は readlink -f と同じく、最後の要素だけは存在しなくてよい。新しく
// 作るファイルも、壊れた symlink の先も、親ディレクトリを解いた位置で判定する。
// 親が解けなければ判定できる場所が無いので、ok を偽にする。
//
// symlink を解く前に filepath.Clean を通してはいけない。Abs、Dir、Join はどれも
// 字面で ".." を畳むので、"link/../x" の link が消え、symlink の先の親ではなく
// 手前のディレクトリで判定してしまう。EvalSymlinks は ".." を実際の親として扱う。
func resolve(path string, depth int) (string, bool) {
	// 循環する symlink で終わらなくならないよう、たどる回数に上限を設ける。
	if depth > 40 {
		return "", false
	}
	if !filepath.IsAbs(path) {
		wd, err := os.Getwd()
		if err != nil {
			return "", false
		}
		path = wd + "/" + path
	}
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved, true
	}
	trimmed := strings.TrimRight(path, "/")
	slash := strings.LastIndex(trimmed, "/")
	parent, base := trimmed[:slash+1], trimmed[slash+1:]
	if base == "" || base == "." || base == ".." {
		return "", false
	}
	dir, err := filepath.EvalSymlinks(parent)
	if err != nil {
		return "", false
	}
	full := filepath.Join(dir, base)
	target, err := os.Readlink(full)
	if err != nil {
		return full, true
	}
	if !filepath.IsAbs(target) {
		target = dir + "/" + target
	}
	return resolve(target, depth+1)
}
