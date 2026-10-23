package main

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestParseStoryObject(t *testing.T) {
	data := []byte(string(rune(0xFEFF)) + `{
		"title": "El gato", "title_en": "The cat", "level": "A1",
		"content": [["María", "María"], ["tiene", "has / owns"], ["un gato", ["a cat"]],
		            [".", ""], ["\n", null], {"es": "Fin", "en": "The end"}]
	}`)
	s, err := parseStory("/x/01-el-gato.json", data)
	if err != nil {
		t.Fatal(err)
	}
	if s.ID != "01-el-gato" || s.Title != "El gato" || s.TitleEn != "The cat" || s.Level != "A1" {
		t.Fatalf("bad metadata: %+v", s)
	}
	if len(s.Tokens) != 6 {
		t.Fatalf("want 6 tokens, got %d", len(s.Tokens))
	}
	if !reflect.DeepEqual(s.Tokens[1].En, []string{"has", "owns"}) {
		t.Fatalf("alternatives not split: %v", s.Tokens[1].En)
	}
	if s.Tokens[3].En != nil || s.Tokens[4].Es != "\n" {
		t.Fatalf("punctuation/paragraph tokens wrong: %+v", s.Tokens[3:5])
	}
	if s.Words != 5 { // María, tiene, un, gato, Fin
		t.Fatalf("want 5 words, got %d", s.Words)
	}
	out, _ := json.Marshal(s.Tokens[3])
	if string(out) != `[".",[]]` {
		t.Fatalf("token encoding: %s", out)
	}
}

func TestParseStoryBareArray(t *testing.T) {
	s, err := parseStory("02-la_casa.json", []byte(`[["Hola", "Hello"]]`))
	if err != nil {
		t.Fatal(err)
	}
	if s.Title != "La casa" {
		t.Fatalf("title from filename: %q", s.Title)
	}
}

func TestParseStoryErrors(t *testing.T) {
	for name, data := range map[string]string{
		"empty":     `{"title": "x", "content": []}`,
		"triple":    `[["a", "b", "c"]]`,
		"not text":  `[[1, "b"]]`,
		"bad json":  `[["a", "b"]`,
		"bad en":    `[["a", 5]]`,
		"not story": `"hello"`,
	} {
		if _, err := parseStory("x.json", []byte(data)); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}

func writeStory(t *testing.T, dir, name, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestAppFlow(t *testing.T) {
	dir := t.TempDir()
	writeStory(t, dir, "01-a.json", `{"title": "A", "content": [["uno", "one"], ["dos", "two"], [".", ""]]}`)
	writeStory(t, dir, "02-broken.json", `{"content": [`)
	statePath := filepath.Join(t.TempDir(), "sub", "state.json")
	app := newApp([]string{dir, filepath.Join(dir, "missing")}, statePath)

	lib := app.handle(reqList, []byte(`{}`))[0].Body.(map[string]any)
	if n := len(lib["stories"].([]storySummary)); n != 1 {
		t.Fatalf("want 1 story, got %d", n)
	}
	if n := len(lib["errors"].([]StoryError)); n != 1 {
		t.Fatalf("want 1 broken file, got %d", n)
	}

	r := app.handle(reqOpen, []byte(`{"id": "01-a"}`))
	if len(r) != 1 || r[0].Type != respStory {
		t.Fatalf("open failed: %+v", r)
	}
	app.handle(reqProgress, []byte(`{"id": "01-a", "token": 2}`))
	app.handle(reqLookup, []byte(`{"id": "01-a", "es": "Dos"}`))
	app.handle(reqLookup, []byte(`{"id": "01-a", "es": "dos"}`))
	app.handle(reqSettings, []byte(`{"textSize": 5}`))

	// Everything must survive a restart.
	app2 := newApp([]string{dir}, statePath)
	p := app2.state.Stories["01-a"]
	if p == nil || p.Token != 2 || p.Lookups["dos"] != 2 {
		t.Fatalf("progress not persisted: %+v", p)
	}
	if app2.state.Settings["textSize"].(float64) != 5 || app2.state.Settings["dots"] != true {
		t.Fatalf("settings not persisted: %v", app2.state.Settings)
	}
	sum := app2.library()["stories"].([]storySummary)[0]
	if !sum.Started || sum.Lookups != 1 || sum.Progress < 0.66 || sum.Progress > 0.67 {
		t.Fatalf("summary wrong: %+v", sum)
	}

	app2.handle(reqProgress, []byte(`{"id": "01-a", "token": 0, "finished": true}`))
	if !app2.state.Stories["01-a"].Finished {
		t.Fatal("finished flag not stored")
	}
	app2.handle(reqReset, []byte(`{"id": "01-a"}`))
	if _, ok := app2.state.Stories["01-a"]; ok {
		t.Fatal("reset did not clear progress")
	}

	if r := app2.handle(reqOpen, []byte(`{"id": "nope"}`)); r[0].Type != respError {
		t.Fatal("expected error for unknown story")
	}
	if r := app2.handle(42, []byte(`{}`)); r[0].Type != respError {
		t.Fatal("expected error for unknown message")
	}
}

func TestLibraryOrder(t *testing.T) {
	dir := t.TempDir()
	for _, id := range []string{"01-a", "02-b", "03-c", "04-d"} {
		writeStory(t, dir, id+".json", `{"title": "`+id+`", "content": [["uno", "one"]]}`)
	}
	app := newApp([]string{dir}, filepath.Join(t.TempDir(), "state.json"))
	clock := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)
	app.now = func() time.Time { return clock }
	for _, id := range []string{"03-c", "02-b"} {
		app.handle(reqOpen, []byte(`{"id": "`+id+`"}`))
		clock = clock.Add(time.Minute)
	}
	var got []string
	for _, s := range app.library()["stories"].([]storySummary) {
		got = append(got, s.ID)
	}
	if strings.Join(got, " ") != "02-b 03-c 01-a 04-d" {
		t.Fatalf("library order: %v", got)
	}
}

// End to end over the TCP framing used by the emulator.
func TestStreamTransport(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	done := make(chan transport)
	go func() {
		c, err := dial("tcp:" + ln.Addr().String())
		if err != nil {
			t.Error(err)
		}
		done <- c
	}()
	server, err := ln.Accept()
	if err != nil {
		t.Fatal(err)
	}
	client := <-done
	srv := &streamTransport{conn: server}
	if err := srv.send(reqList, []byte(`{"a":1}`)); err != nil {
		t.Fatal(err)
	}
	typ, body, err := client.recv()
	if err != nil || typ != reqList || string(body) != `{"a":1}` {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
	if err := client.send(msgSystemTerminate, []byte("close")); err != nil {
		t.Fatal(err)
	}
	typ, body, err = srv.recv()
	if err != nil || typ != -1 || string(body) != "close" {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
}

func TestHeaderEncoding(t *testing.T) {
	h := encodeHeader(-2, 300)
	if !reflect.DeepEqual(h, []byte{0xfe, 0xff, 0xff, 0xff, 0x2c, 0x01, 0, 0}) {
		t.Fatalf("header bytes %v", h)
	}
	typ, n, err := decodeHeader(h)
	if err != nil || typ != -2 || n != 300 {
		t.Fatal("decode mismatch")
	}
	if _, _, err := decodeHeader(encodeHeader(1, maxMessageLength+1)); err == nil {
		t.Fatal("oversized message accepted")
	}
}
