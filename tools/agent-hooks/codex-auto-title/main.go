// codex-auto-title は Codex の notify フック。ターンが終わったスレッドにまだ名前が
// 無ければ、最初のプロンプトとブランチの issue 番号から名前を付ける。
//
//	codex-auto-title <notification-json>
//
// codex-auto が起動した app-server に CODEX_AUTO_TITLE_SOCKET 経由で接続する。
// 変数が無いのは codex-auto の外で動いた場合なので、何もしない。
//
// 名前付けはおまけなので、何が起きても標準出力に何も書かず exit 0 で終わる。
// CODEX_AUTO_TITLE_DEBUG=1 のときだけ失敗の理由を標準エラーに書く。
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"time"
)

// 接続前から数えた全体の上限。テストが短くできるよう変数にしている。
var budget = 3 * time.Second

func main() {
	run(os.Args[1:], os.Getenv, os.Stderr)
}

func run(args []string, getenv func(string) string, stderr io.Writer) {
	if err := name(args, getenv("CODEX_AUTO_TITLE_SOCKET")); err != nil && getenv("CODEX_AUTO_TITLE_DEBUG") == "1" {
		fmt.Fprintf(stderr, "codex-auto-title: %v\n", err)
	}
}

func name(args []string, socket string) error {
	if len(args) == 0 || args[0] == "" || socket == "" {
		return nil
	}
	var n notification
	if err := json.Unmarshal([]byte(args[0]), &n); err != nil {
		return err
	}
	if !n.eligible() {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), budget)
	defer cancel()
	client, err := connect(ctx, socket)
	if err != nil {
		return err
	}
	defer client.close()
	_, err = setAutomaticTitle(ctx, n, client)
	return err
}
