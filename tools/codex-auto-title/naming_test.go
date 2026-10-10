package main

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

type call struct {
	method string
	params map[string]any
}

type fakeClient struct {
	calls     []call
	responses []any
	err       error
}

func (f *fakeClient) request(_ context.Context, method string, params map[string]any) (any, error) {
	f.calls = append(f.calls, call{method, params})
	if f.err != nil {
		return nil, f.err
	}
	if len(f.responses) == 0 {
		return nil, nil
	}
	response := f.responses[0]
	f.responses = f.responses[1:]
	return response, nil
}

func turn(fields map[string]any) notification {
	n := notification{"type": "agent-turn-complete", "thread-id": "thread-1"}
	for k, v := range fields {
		n[k] = v
	}
	return n
}

func thread(fields map[string]any) map[string]any {
	return map[string]any{"thread": fields}
}

var readParams = map[string]any{"threadId": "thread-1", "includeTurns": false}

func TestSetsAnUnnamedRootThread(t *testing.T) {
	client := &fakeClient{responses: []any{
		thread(map[string]any{"name": nil, "gitInfo": map[string]any{"branch": "feature/#456-title"}}),
		thread(map[string]any{"name": nil}),
		map[string]any{},
	}}
	changed, err := setAutomaticTitle(context.Background(), turn(map[string]any{
		"cwd":            "/work/dotfiles",
		"input-messages": []any{"セッション名を設定する"},
	}), client)
	if err != nil || !changed {
		t.Fatalf("changed = %v, err = %v", changed, err)
	}
	want := []call{
		{"thread/read", readParams},
		{"thread/read", readParams},
		{"thread/name/set", map[string]any{"threadId": "thread-1", "name": "#456 セッション名を設定する"}},
	}
	if !reflect.DeepEqual(client.calls, want) {
		t.Errorf("calls = %v, want %v", client.calls, want)
	}
}

// 2 回目の read の branch では名前を作り直さない
func TestUsesTheFirstReadBranch(t *testing.T) {
	client := &fakeClient{responses: []any{
		thread(map[string]any{"gitInfo": map[string]any{"branch": "feat/1-a"}}),
		thread(map[string]any{"gitInfo": map[string]any{"branch": "feat/2-b"}}),
	}}
	if _, err := setAutomaticTitle(context.Background(), turn(map[string]any{"input-messages": []any{"名前"}}), client); err != nil {
		t.Fatal(err)
	}
	if got := client.calls[2].params["name"]; got != "#1 名前" {
		t.Errorf("name = %v", got)
	}
}

func TestSkipsIneligibleThreads(t *testing.T) {
	cases := map[string]any{
		"manual name":          thread(map[string]any{"name": "手動の名前"}),
		"child":                thread(map[string]any{"parentThreadId": "parent"}),
		"child with empty id":  thread(map[string]any{"parentThreadId": ""}),
		"ephemeral":            thread(map[string]any{"ephemeral": true}),
		"thread is not object": map[string]any{"thread": "x"},
		"no response":          nil,
	}
	for name, response := range cases {
		t.Run(name, func(t *testing.T) {
			client := &fakeClient{responses: []any{response}}
			changed, err := setAutomaticTitle(context.Background(), turn(nil), client)
			if err != nil || changed || len(client.calls) != 1 {
				t.Errorf("changed = %v, err = %v, calls = %d", changed, err, len(client.calls))
			}
		})
	}
}

func TestTreatsTheseThreadsAsUnnamedRoots(t *testing.T) {
	cases := map[string]any{
		"null name":            thread(map[string]any{"name": nil}),
		"non-string name":      thread(map[string]any{"name": 1}),
		"blank name":           thread(map[string]any{"name": " 　\n"}),
		"null parent":          thread(map[string]any{"parentThreadId": nil}),
		"ephemeral false":      thread(map[string]any{"ephemeral": false}),
		"ephemeral non-bool":   thread(map[string]any{"ephemeral": "true"}),
		"direct thread object": map[string]any{"name": nil},
		"null thread member":   map[string]any{"thread": nil},
	}
	for name, response := range cases {
		t.Run(name, func(t *testing.T) {
			client := &fakeClient{responses: []any{response, response}}
			changed, err := setAutomaticTitle(context.Background(), turn(nil), client)
			if err != nil || !changed {
				t.Errorf("changed = %v, err = %v", changed, err)
			}
		})
	}
}

func TestLosesARaceToManualRename(t *testing.T) {
	client := &fakeClient{responses: []any{
		thread(map[string]any{"name": nil}),
		thread(map[string]any{"name": "先に付いた名前"}),
	}}
	changed, err := setAutomaticTitle(context.Background(), turn(map[string]any{"input-messages": []any{"自動の名前"}}), client)
	if err != nil || changed || len(client.calls) != 2 {
		t.Errorf("changed = %v, err = %v, calls = %d", changed, err, len(client.calls))
	}
}

func TestReturnsRequestErrors(t *testing.T) {
	want := errors.New("boom")
	client := &fakeClient{err: want}
	if changed, err := setAutomaticTitle(context.Background(), turn(nil), client); !errors.Is(err, want) || changed {
		t.Errorf("changed = %v, err = %v", changed, err)
	}
}

func TestEligibleNotifications(t *testing.T) {
	cases := []struct {
		n    notification
		want bool
	}{
		{notification{"type": "agent-turn-complete", "thread-id": "t"}, true},
		{notification{"type": "agent-turn-complete", "thread-id": ""}, true},
		{notification{"type": "agent-turn-complete", "thread-id": 1}, false},
		{notification{"type": "agent-turn-complete"}, false},
		{notification{"type": "other", "thread-id": "t"}, false},
		{nil, false},
	}
	for _, c := range cases {
		if got := c.n.eligible(); got != c.want {
			t.Errorf("%v.eligible() = %v, want %v", c.n, got, c.want)
		}
	}
}
