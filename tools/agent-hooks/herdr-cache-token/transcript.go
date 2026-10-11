package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"time"
)

const tailBytes = 512 * 1024

// obj は transcript や payload の JSON オブジェクト。キーを大文字・小文字の区別付きで
// 引き、値ごとに型を確かめるため struct ではなく map に読む。struct へのデコードは
// キーの大文字・小文字を無視し、型の合わないフィールドが 1 つあるだけで行全体を捨てる。
type obj map[string]json.RawMessage

// parseObj はオブジェクトでない JSON (null、配列、スカラー) と不正な JSON に nil を返す。
func parseObj(data []byte) obj {
	var o obj
	if json.Unmarshal(data, &o) != nil {
		return nil
	}
	return o
}

// str は空でない文字列の値を返す。欠落と文字列以外 (null を含む) は空文字列になる。
func (o obj) str(key string) string {
	var s string
	if json.Unmarshal(o[key], &s) != nil {
		return ""
	}
	return s
}

func (o obj) obj(key string) obj {
	return parseObj(o[key])
}

// count はトークン数。正の有限数でなければ 0 とみなす。1e400 のように float64 に
// 収まらない値は Unmarshal が失敗するので、JavaScript の Infinity と同じく 0 になる。
func (o obj) count(key string) float64 {
	if n, ok := o.number(key); ok && n > 0 {
		return n
	}
	return 0
}

// number は数値の値を返す。欠落、null、数値以外は ok が false になる。
func (o obj) number(key string) (float64, bool) {
	var n *float64
	if json.Unmarshal(o[key], &n) != nil || n == nil {
		return 0, false
	}
	return *n, true
}

// sidechain は isSidechain が欠落か厳密な false のときだけ false を返す。
// null や未知の形はメインチェーンの証拠にならない。
func (o obj) sidechain() bool {
	raw, ok := o["isSidechain"]
	return ok && string(raw) != "false"
}

// epoch は RFC 3339 のタイムスタンプをミリ秒精度の epoch 秒にする。旧実装の
// Date.parse と同じ精度に揃え、stale_after との比較結果を変えないため。
// Date.parse が受け付ける RFC 3339 以外の形は、transcript に現れないので扱わない。
func (o obj) epoch(key string) (float64, bool) {
	t, err := time.Parse(time.RFC3339, o.str(key))
	if err != nil {
		return 0, false
	}
	return float64(t.UnixMilli()) / 1000, true
}

// readTail は transcript の末尾 tailBytes を読み、JSON オブジェクトの行を返す。
// 書きかけの最終行や不正な行は捨てる。
func readTail(path string) ([]obj, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, err
	}
	start := max(0, info.Size()-tailBytes)
	data := make([]byte, info.Size()-start)
	n, err := io.ReadFull(io.NewSectionReader(f, start, int64(len(data))), data)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		return nil, err
	}
	data = data[:n]
	if start > 0 {
		// 窓の先頭は行の途中から始まるので、最初の改行までを捨てる。
		if nl := bytes.IndexByte(data, '\n'); nl >= 0 {
			data = data[nl+1:]
		} else {
			data = nil
		}
	}
	var objs []obj
	for line := range bytes.SplitSeq(data, []byte("\n")) {
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		if o := parseObj(line); o != nil {
			objs = append(objs, o)
		}
	}
	return objs, nil
}

// group は message.id ごとにまとめた assistant メッセージ。transcript は content
// block ごとに 1 行を書き、usage は各行で繰り返されるので、合計してはならない。
type group struct {
	mid        string
	firstIdx   int
	stopReason string
	usage      obj
	ts         float64
	hasTS      bool
}

func groupAssistants(objs []obj, sessionID string) []*group {
	var order []*group
	seen := map[string]*group{}
	for idx, o := range objs {
		if o.str("type") != "assistant" || o.sidechain() {
			continue
		}
		message := o.obj("message")
		if message == nil {
			continue
		}
		mid := message.str("id")
		if mid == "" || o.str("sessionId") != sessionID {
			continue
		}
		g := seen[mid]
		if g == nil {
			g = &group{mid: mid, firstIdx: idx}
			g.ts, g.hasTS = o.epoch("timestamp")
			seen[mid] = g
			order = append(order, g)
		}
		if stop := message.str("stop_reason"); stop != "" {
			g.stopReason = stop
		}
		if usage := message.obj("usage"); usage != nil {
			g.usage = usage
		}
	}
	return order
}

// terminal は完了したメッセージかを返す。stop_reason がないのは書き込み途中であり、
// usage がすべて 0 のエントリはキャッシュについて何も示さない。
func (g *group) terminal() bool {
	switch g.stopReason {
	case "", "tool_use", "pause_turn":
		return false
	}
	return g.usage.count("input_tokens") > 0 ||
		g.usage.count("cache_read_input_tokens") > 0 ||
		g.usage.count("cache_creation_input_tokens") > 0
}

// newestTerminal は cursor より後の最新の完了エントリの添字を返す。なければ -1。
// staleAfter は、待つのを諦めたターンの遅れて届いたエントリを次のターンのものと
// 取り違えないための下限。
func newestTerminal(groups []*group, cursor string, staleAfter *float64) int {
	start := 0
	if cursor != "" {
		found := -1
		for i, g := range groups {
			if g.mid == cursor {
				found = i
			}
		}
		if found < 0 {
			// cursor が末尾の窓から外れたので「cursor より後」は分からない。
			// ここで推測すると前のターンを拾い直してしまう。
			return -1
		}
		start = found + 1
	}
	for i := len(groups) - 1; i >= start; i-- {
		g := groups[i]
		if !g.terminal() {
			continue
		}
		if staleAfter != nil && (!g.hasTS || g.ts <= *staleAfter) {
			continue
		}
		return i
	}
	return -1
}

// creationTTL はこのメッセージがキャッシュを書いた TTL の秒数。書いていないか
// 書いた TTL が分からなければ 0。内訳は合計が書き込みを認めるときだけ読む。
// usage.iterations[] は advisor が自分の 5m キャッシュを書くので見ない。
func creationTTL(usage obj) int {
	if usage.count("cache_creation_input_tokens") == 0 {
		return 0
	}
	creation := usage.obj("cache_creation")
	// 両方が正なら短いほうの失効に合わせる。
	if creation.count("ephemeral_5m_input_tokens") > 0 {
		return 300
	}
	if creation.count("ephemeral_1h_input_tokens") > 0 {
		return 3600
	}
	return 0
}

// ttl は groups[idx] が触れたキャッシュの TTL の秒数。分からなければ 0。
//
// 読むだけのリフレッシュは自分では何も書かないので、同じ transcript で直近に
// 書かれた TTL を引き継ぐ。値を保存せず毎回さかのぼるのは、古くなった値を
// 引き継がないため。引き継げるのはこの場合だけで、内訳のない書き込みや、
// キャッシュに触れていないターンは不明として扱う。
func ttl(groups []*group, idx int) int {
	usage := groups[idx].usage
	if own := creationTTL(usage); own != 0 {
		return own
	}
	creation := usage.obj("cache_creation")
	wroteNothing := usage.count("cache_creation_input_tokens") == 0 &&
		creation.count("ephemeral_5m_input_tokens") == 0 &&
		creation.count("ephemeral_1h_input_tokens") == 0
	if !wroteNothing || usage.count("cache_read_input_tokens") == 0 {
		return 0
	}
	for i := idx - 1; i >= 0; i-- {
		if kind := creationTTL(groups[i].usage); kind != 0 {
			return kind
		}
	}
	return 0
}

// requestStart はリクエストを開いた user エントリのタイムスタンプ。実際の開始は
// これより少し後なので、表示する失効時刻は早めに倒れる。
func requestStart(objs []obj, g *group, sessionID string) (float64, bool) {
	for i := g.firstIdx - 1; i >= 0; i-- {
		o := objs[i]
		if o.str("type") != "user" || o.sidechain() || o.str("sessionId") != sessionID {
			continue
		}
		// 直近の user エントリに使える時刻がなければ開始は分からない。さらに
		// さかのぼると前のターンの時刻を借りてしまう。
		return o.epoch("timestamp")
	}
	return 0, false
}
