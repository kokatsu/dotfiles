package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// macOS の Unix socket のパスは 104 バイトまで。Nix のビルドディレクトリ配下の
// t.TempDir() は長くなりうるので、そのときは /tmp に作る。
func socketPath(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if len(dir) > 80 {
		var err error
		if dir, err = os.MkdirTemp("/tmp", "cat"); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.RemoveAll(dir) })
	}
	return filepath.Join(dir, "s")
}

type server struct {
	socket  string
	accepts atomic.Int32
	mu      sync.Mutex
	host    string
	path    string
}

// serve は WebSocket の接続ごとに script を動かす模擬 app-server を立てる。
func serve(t *testing.T, script func(ctx context.Context, conn *websocket.Conn)) *server {
	t.Helper()
	s := &server{socket: socketPath(t)}
	listener, err := net.Listen("unix", s.socket)
	if err != nil {
		t.Fatal(err)
	}
	httpServer := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.accepts.Add(1)
		s.mu.Lock()
		s.host, s.path = r.Host, r.URL.Path
		s.mu.Unlock()
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		script(r.Context(), conn)
	})}
	go func() { _ = httpServer.Serve(listener) }()
	t.Cleanup(func() { _ = httpServer.Close() })
	return s
}

func receive(ctx context.Context, conn *websocket.Conn) map[string]any {
	_, data, err := conn.Read(ctx)
	if err != nil {
		return nil
	}
	var message map[string]any
	_ = json.Unmarshal(data, &message)
	return message
}

func send(ctx context.Context, conn *websocket.Conn, message string) {
	_ = conn.Write(ctx, websocket.MessageText, []byte(message))
}

const turnJSON = `{"type":"agent-turn-complete","thread-id":"thread-1","cwd":"/work/dotfiles","input-messages":["名前を付ける"]}`

func TestNamesAThreadThroughTheAppServer(t *testing.T) {
	var received []map[string]any
	done := make(chan struct{})
	s := serve(t, func(ctx context.Context, conn *websocket.Conn) {
		defer close(done)
		record := func() { received = append(received, receive(ctx, conn)) }
		record()
		// 応答を待つ間の通知と別 ID の応答は読み捨てられる
		send(ctx, conn, `{"method":"thread/started","params":{}}`)
		send(ctx, conn, `{"id":99,"error":{"message":"not yours"}}`)
		send(ctx, conn, `{"id":1,"result":{}}`)
		record()
		record()
		send(ctx, conn, `{"id":2,"result":{"thread":{"name":null,"gitInfo":{"branch":"feat/7-x"}}}}`)
		record()
		send(ctx, conn, `{"id":3,"result":{"thread":{"name":null}}}`)
		record()
		send(ctx, conn, `{"id":4,"result":{}}`)
		_, _, _ = conn.Read(ctx)
	})

	if err := name([]string{turnJSON, "ignored"}, s.socket); err != nil {
		t.Fatal(err)
	}
	<-done
	read := map[string]any{"threadId": "thread-1", "includeTurns": false}
	want := []map[string]any{
		{"id": 1.0, "method": "initialize", "params": map[string]any{
			"clientInfo":   map[string]any{"name": "codex-auto-title", "version": "1.0.0"},
			"capabilities": map[string]any{},
		}},
		{"method": "initialized", "params": map[string]any{}},
		{"id": 2.0, "method": "thread/read", "params": read},
		{"id": 3.0, "method": "thread/read", "params": read},
		{"id": 4.0, "method": "thread/name/set", "params": map[string]any{"threadId": "thread-1", "name": "#7 名前を付ける"}},
	}
	if !reflect.DeepEqual(received, want) {
		t.Errorf("received %v\nwant %v", received, want)
	}
	if s.host != "localhost" || s.path != "/" {
		t.Errorf("host = %q, path = %q", s.host, s.path)
	}
}

func TestFailsOnAnErrorResponse(t *testing.T) {
	for _, reply := range []string{`{"id":2,"error":{"code":-1}}`, `{"id":2,"error":null}`} {
		t.Run(reply, func(t *testing.T) {
			var methods []any
			done := make(chan struct{})
			s := serve(t, func(ctx context.Context, conn *websocket.Conn) {
				defer close(done)
				receive(ctx, conn)
				send(ctx, conn, `{"id":1,"result":{}}`)
				receive(ctx, conn)
				receive(ctx, conn)
				send(ctx, conn, reply)
				for m := receive(ctx, conn); m != nil; m = receive(ctx, conn) {
					methods = append(methods, m["method"])
				}
			})
			if err := name([]string{turnJSON}, s.socket); err == nil {
				t.Error("expected an error")
			}
			<-done
			if len(methods) != 0 {
				t.Errorf("sent %v after the error", methods)
			}
		})
	}
}

func TestSkipsWithoutConnecting(t *testing.T) {
	s := serve(t, func(context.Context, *websocket.Conn) {})
	cases := map[string][]string{
		"no argument":         nil,
		"empty argument":      {""},
		"other event":         {`{"type":"other","thread-id":"thread-1"}`},
		"non-string id":       {`{"type":"agent-turn-complete","thread-id":1}`},
		"null":                {`null`},
		"malformed JSON":      {`{`},
		"non-object JSON":     {`[]`},
		"missing socket":      {turnJSON},
		"empty socket string": {turnJSON},
	}
	for label, args := range cases {
		socket := s.socket
		if strings.Contains(label, "socket") {
			socket = ""
		}
		_ = name(args, socket)
	}
	if n := s.accepts.Load(); n != 0 {
		t.Errorf("connected %d times", n)
	}
}

// 予算は接続前から数える。close handshake も待たないので、名前を付けたあと close
// frame に応えない相手でも予算を超えない。
func TestStaysWithinTheBudget(t *testing.T) {
	budget = 300 * time.Millisecond
	t.Cleanup(func() { budget = 3 * time.Second })

	stalledHandshake := socketPath(t)
	listener, err := net.Listen("unix", stalledHandshake)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { _ = conn.Close() })
		}
	}()
	// 読むのをやめた相手は close frame にも応えない
	stop := make(chan struct{})
	t.Cleanup(func() { close(stop) })
	silent := serve(t, func(ctx context.Context, conn *websocket.Conn) {
		receive(ctx, conn)
		<-stop
	})
	named := serve(t, func(ctx context.Context, conn *websocket.Conn) {
		receive(ctx, conn)
		send(ctx, conn, `{"id":1,"result":{}}`)
		receive(ctx, conn)
		for id := 2; id <= 4; id++ {
			receive(ctx, conn)
			send(ctx, conn, fmt.Sprintf(`{"id":%d,"result":{}}`, id))
		}
		<-stop
	})

	cases := []struct {
		label   string
		socket  string
		wantErr bool
	}{
		{"stalled handshake", stalledHandshake, true},
		{"silent server", silent.socket, true},
		{"close frame ignored after naming", named.socket, false},
	}
	for _, c := range cases {
		t.Run(c.label, func(t *testing.T) {
			start := time.Now()
			if err := name([]string{turnJSON}, c.socket); (err != nil) != c.wantErr {
				t.Errorf("err = %v", err)
			}
			if elapsed := time.Since(start); elapsed > budget+500*time.Millisecond {
				t.Errorf("took %v", elapsed)
			}
		})
	}
}

func TestReportsErrorsOnlyInDebugMode(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing")
	for debug, want := range map[string]bool{"": false, "0": false, "1": true} {
		var stderr bytes.Buffer
		env := map[string]string{"CODEX_AUTO_TITLE_SOCKET": missing, "CODEX_AUTO_TITLE_DEBUG": debug}
		run([]string{turnJSON}, func(k string) string { return env[k] }, &stderr)
		if got := strings.HasPrefix(stderr.String(), "codex-auto-title: "); got != want {
			t.Errorf("debug=%q: stderr = %q", debug, stderr.String())
		}
	}
}
