package main

import (
	"os"
	"path/filepath"
	"testing"
)

// /nix/store の実体は要らない。壊れた symlink の先も判定の対象になるので、
// 存在しないストアパスへのリンクで足りる。
func TestIsManaged(t *testing.T) {
	dir := t.TempDir()
	link := func(name, target string) string {
		p := filepath.Join(dir, name)
		if err := os.Symlink(target, p); err != nil {
			t.Fatal(err)
		}
		return p
	}
	plain := filepath.Join(dir, "plain")
	if err := os.WriteFile(plain, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	storeLink := link("storelink", "/nix/store/zzzz-nonexistent")
	storeDir := link("storedir", "/nix/store")
	repoLink := link("repolink", plain)
	chain := link("chain", storeLink)
	relative := link("relative", "storelink")
	loop := link("loop", filepath.Join(dir, "loop"))

	cases := []struct {
		path string
		want bool
	}{
		{storeLink, true},
		{filepath.Join(storeDir, "new.txt"), true},
		{chain, true},
		{relative, true},
		{repoLink, false},
		{plain, false},
		{filepath.Join(dir, "new.txt"), false},
		{filepath.Join(dir, "nodir", "new.txt"), false},
		{loop, false},
	}
	for _, c := range cases {
		if got := isManaged(c.path); got != c.want {
			t.Errorf("isManaged(%s) = %v, want %v", c.path, got, c.want)
		}
	}
}

// ".." は symlink の先の親を指す。字面で畳むと手前のディレクトリになり、
// /nix/store の配下への書き込みを見逃す。
func TestResolveDotDotAfterSymlink(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	sub := filepath.Join(dir, "real", "sub")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(sub, filepath.Join(dir, "link")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("link/../target", filepath.Join(dir, "rel")); err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(dir, "real", "new.txt")
	if got, ok := resolve(filepath.Join(dir, "link")+"/../new.txt", 0); !ok || got != want {
		t.Errorf("link/../new.txt resolved to %q, want %q", got, want)
	}
	want = filepath.Join(dir, "real", "target")
	if got, ok := resolve(filepath.Join(dir, "rel"), 0); !ok || got != want {
		t.Errorf("relative target link/../target resolved to %q, want %q", got, want)
	}
}
