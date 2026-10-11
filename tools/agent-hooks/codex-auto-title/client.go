package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"

	"github.com/coder/websocket"
)

// appServerClient は codex app-server の WebSocket に 1 本だけ接続し、要求を 1 件ずつ
// 順に送る。応答を待つ間に届いた通知や別 ID の応答は読み捨てる。
type appServerClient struct {
	conn   *websocket.Conn
	nextID int
}

func connect(ctx context.Context, socket string) (*appServerClient, error) {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			var dialer net.Dialer
			return dialer.DialContext(ctx, "unix", socket)
		},
	}
	conn, _, err := websocket.Dial(ctx, "ws://localhost/", &websocket.DialOptions{
		HTTPClient: &http.Client{Transport: transport},
	})
	if err != nil {
		return nil, err
	}
	// thread/read の応答や無関係な通知が既定の 32KiB を超えても読めるようにする。
	conn.SetReadLimit(-1)
	client := &appServerClient{conn: conn, nextID: 1}

	if _, err := client.request(ctx, "initialize", map[string]any{
		"clientInfo":   map[string]any{"name": "codex-auto-title", "version": "1.0.0"},
		"capabilities": map[string]any{},
	}); err != nil {
		client.close()
		return nil, err
	}
	if err := client.write(ctx, map[string]any{"method": "initialized", "params": map[string]any{}}); err != nil {
		client.close()
		return nil, err
	}
	return client, nil
}

func (c *appServerClient) write(ctx context.Context, message any) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}
	return c.conn.Write(ctx, websocket.MessageText, data)
}

func (c *appServerClient) request(ctx context.Context, method string, params map[string]any) (any, error) {
	id := c.nextID
	c.nextID++
	if err := c.write(ctx, map[string]any{"id": id, "method": method, "params": params}); err != nil {
		return nil, err
	}
	for {
		kind, data, err := c.conn.Read(ctx)
		if err != nil {
			return nil, err
		}
		if kind != websocket.MessageText {
			return nil, errors.New("app-server sent a binary WebSocket message")
		}
		var response map[string]json.RawMessage
		if err := json.Unmarshal(data, &response); err != nil {
			return nil, err
		}
		var responseID any
		if raw, ok := response["id"]; !ok || json.Unmarshal(raw, &responseID) != nil || responseID != float64(id) {
			continue
		}
		// error が null でも失敗として扱う
		if raw, ok := response["error"]; ok {
			return nil, fmt.Errorf("app-server request failed: %s", raw)
		}
		var result any
		if raw, ok := response["result"]; ok {
			if err := json.Unmarshal(raw, &result); err != nil {
				return nil, err
			}
		}
		return result, nil
	}
}

// close は close handshake を待たない。websocket.Conn.Close は context を受け取らず、
// 送信と応答待ちに固定の 5 秒ずつを使うので、全体の時間予算を超えてしまう。
func (c *appServerClient) close() {
	_ = c.conn.CloseNow()
}
