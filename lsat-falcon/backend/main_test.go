package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"unicode/utf8"
)

// writeDeck writes a two-question deck in build_data.py's format.
func writeDeck(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	meta := `{"format":1,"q":[[1,1,1,3,0,0,"B",0],[1,1,2,2,0,0,"C",0]],"groups":[[1,1,[0,1]]]}`
	q0 := `{"q":"Stem one","a":{"A":"a","B":"b"},"s":null,"e":"B) Right."}`
	q1 := `{"q":"Stem two","a":{"A":"a","C":"c"},"s":{"A":40,"C":60},"e":""}`
	g0 := `"The passage — with a dash."`
	content := q0 + q1 + g0
	idx := map[string][][2]int{
		"q": {{0, len(q0)}, {len(q0), len(q1)}},
		"g": {{len(q0) + len(q1), len(g0)}},
	}
	idxJSON, _ := json.Marshal(idx)
	for name, data := range map[string]string{"meta.json": meta, "content.dat": content, "content.idx": string(idxJSON)} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(data), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestHelloAndQuestion(t *testing.T) {
	a := newApp(writeDeck(t), filepath.Join(t.TempDir(), "state.json"))
	if a.loadErr != nil {
		t.Fatal(a.loadErr)
	}
	replies := a.handle(reqHello, []byte("{}"))
	if len(replies) != 2 || replies[0].Type != respState || replies[1].Type != respMeta {
		t.Fatalf("hello replies: %+v", replies)
	}

	replies = a.handle(reqQuestion, []byte(`{"i":1}`))
	if len(replies) != 1 || replies[0].Type != respQuestion {
		t.Fatalf("question reply: %+v", replies)
	}
	data, _ := json.Marshal(replies[0].Body)
	var q struct {
		I       int            `json:"i"`
		G       int            `json:"g"`
		Q       string         `json:"q"`
		Passage string         `json:"passage"`
		S       map[string]int `json:"s"`
	}
	if err := json.Unmarshal(data, &q); err != nil {
		t.Fatal(err)
	}
	if q.I != 1 || q.G != 0 || q.Q != "Stem two" || q.Passage != "The passage — with a dash." || q.S["C"] != 60 {
		t.Fatalf("question 1: %+v", q)
	}

	if r := a.handle(reqQuestion, []byte(`{"i":7}`)); len(r) != 1 || r[0].Type != respError {
		t.Fatalf("missing question: %+v", r)
	}
}

func TestStatePersists(t *testing.T) {
	deck := writeDeck(t)
	path := filepath.Join(t.TempDir(), "state.json")
	a := newApp(deck, path)
	a.handle(reqSettings, []byte(`{"shuffle":false,"levels":[2,4]}`))
	a.handle(reqPosition, []byte(`{"position":"PT1-S1-Q2"}`))

	b := newApp(deck, path)
	if b.state.Position != "PT1-S1-Q2" || b.state.Settings["shuffle"] != false {
		t.Fatalf("state not restored: %+v", b.state)
	}
	data, _ := json.Marshal(b.handle(reqHello, nil)[0].Body)
	if !strings.Contains(string(data), `"levels":[2,4]`) {
		t.Fatalf("hello state: %s", data)
	}
}

func TestMissingDeck(t *testing.T) {
	a := newApp(t.TempDir(), filepath.Join(t.TempDir(), "state.json"))
	if r := a.handle(reqHello, nil); len(r) != 1 || r[0].Type != respError {
		t.Fatalf("expected an error reply, got %+v", r)
	}
}

type recorder struct{ sent [][]byte }

func (r *recorder) send(msgType int32, body []byte) error {
	r.sent = append(r.sent, append([]byte(strconv.Itoa(int(msgType))+"|"), body...))
	return nil
}

func TestChunking(t *testing.T) {
	// Multi-byte text straddling every chunk boundary.
	text := strings.Repeat("é—ab", chunkSize/3)
	rec := &recorder{}
	if err := sendChunked(rec.send, reply{respMeta, map[string]string{"t": text}}); err != nil {
		t.Fatal(err)
	}
	if len(rec.sent) < 2 {
		t.Fatalf("expected several chunks, got %d", len(rec.sent))
	}
	var joined bytes.Buffer
	for i, msg := range rec.sent {
		typ, rest, _ := bytes.Cut(msg, []byte("|"))
		head, piece, _ := bytes.Cut(rest, []byte("\n"))
		if string(typ) != "190" || string(head) != "101 "+strconv.Itoa(i)+" "+strconv.Itoa(len(rec.sent)) {
			t.Fatalf("chunk %d header %q/%q", i, typ, head)
		}
		if !utf8.Valid(piece) || len(piece) > chunkSize {
			t.Fatalf("chunk %d is not valid UTF-8 or too long (%d)", i, len(piece))
		}
		joined.Write(piece)
	}
	var back map[string]string
	if err := json.Unmarshal(joined.Bytes(), &back); err != nil || back["t"] != text {
		t.Fatal("chunks don't join back into the message")
	}

	rec = &recorder{}
	_ = sendChunked(rec.send, reply{respState, map[string]string{"small": "yes"}})
	if len(rec.sent) != 1 || !strings.HasPrefix(string(rec.sent[0]), "100|") {
		t.Fatalf("small reply should go unchunked: %q", rec.sent)
	}
}

func TestRealDeck(t *testing.T) {
	dir := filepath.Join("..", "build", "data")
	if _, err := os.Stat(filepath.Join(dir, "meta.json")); err != nil {
		t.Skip("run tools/build_data.py first")
	}
	a := newApp(dir, filepath.Join(t.TempDir(), "state.json"))
	if a.loadErr != nil {
		t.Fatal(a.loadErr)
	}
	for i := range a.offsets.Q {
		q, err := a.question(i)
		if err != nil {
			t.Fatal(err)
		}
		data, _ := json.Marshal(q)
		if len(data) > chunkSize*4 {
			t.Fatalf("question %d is %d bytes", i, len(data))
		}
	}
}

func TestHelloRetriesAMissingDeck(t *testing.T) {
	dir := t.TempDir()
	a := newApp(dir, filepath.Join(t.TempDir(), "state.json"))
	replies := a.handle(reqHello, []byte("{}"))
	if len(replies) != 1 || replies[0].Type != respError {
		t.Fatalf("hello without a deck: %+v", replies)
	}
	msg := fmt.Sprint(replies[0].Body)
	if !strings.Contains(msg, "meta.json is missing") || strings.Contains(msg, dir) {
		t.Fatalf("reason: %s", msg)
	}
}
