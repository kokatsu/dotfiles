package main

import "context"

type rpcClient interface {
	request(ctx context.Context, method string, params map[string]any) (any, error)
}

// notification は Codex の notify が argv で渡す JSON。値の型が揃っている保証はないので
// any のまま持ち、使う箇所で型を確かめる。
type notification map[string]any

// eligible は app-server に接続する価値があるかを返す。元の実装は接続して初期化して
// から判定していたが、無関係な通知のために接続する必要はない。
func (n notification) eligible() bool {
	_, ok := n["thread-id"].(string)
	return n["type"] == "agent-turn-complete" && ok
}

// unwrapThread は thread/read の応答から thread を取り出す。JavaScript の
// `response.thread ?? response` と同じく、thread が無いか null なら応答そのものを使う。
func unwrapThread(response any) map[string]any {
	object, ok := response.(map[string]any)
	if !ok {
		return nil
	}
	candidate, ok := object["thread"]
	if !ok || candidate == nil {
		return object
	}
	thread, _ := candidate.(map[string]any)
	return thread
}

func isUnnamedRootThread(thread map[string]any) bool {
	if thread == nil || thread["ephemeral"] == true {
		return false
	}
	if parent, ok := thread["parentThreadId"]; ok && parent != nil {
		return false
	}
	name, ok := thread["name"].(string)
	return !ok || jsTrim(name) == ""
}

func setAutomaticTitle(ctx context.Context, n notification, client rpcClient) (bool, error) {
	if !n.eligible() {
		return false, nil
	}
	threadID := n["thread-id"].(string)
	read := func() (map[string]any, error) {
		response, err := client.request(ctx, "thread/read", map[string]any{"threadId": threadID, "includeTurns": false})
		return unwrapThread(response), err
	}

	initial, err := read()
	if err != nil || !isUnnamedRootThread(initial) {
		return false, err
	}
	gitInfo, _ := initial["gitInfo"].(map[string]any)
	title := makeTitle(n["input-messages"], n["cwd"], gitInfo["branch"])

	// 書き込む直前に読み直し、それまでに付いた手動の名前を上書きしない。読み直しと
	// 書き込みの間の rename とは競合しうる。
	current, err := read()
	if err != nil || !isUnnamedRootThread(current) {
		return false, err
	}
	if _, err := client.request(ctx, "thread/name/set", map[string]any{"threadId": threadID, "name": title}); err != nil {
		return false, err
	}
	return true, nil
}
