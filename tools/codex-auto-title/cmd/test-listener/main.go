// test-listener は scripts/test-codex-auto.sh の模擬 app-server。引数の Unix socket を
// 作って SIGTERM まで待つだけで、接続には応答しない。
package main

import (
	"net"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	listener, err := net.Listen("unix", os.Args[1])
	if err != nil {
		panic(err)
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM)
	<-signals
	_ = listener.Close()
}
