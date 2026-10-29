package main

import (
	"encoding/json"
	"fmt"
	"net"
	"path/filepath"
	"strings"
	"testing"

	"github.com/thooton/tablet/tools/appload"
)

// Harry Potter is about 2 MB, far more than one packet may hold: it must
// stream in chunks that each fit, and that add up to the book.
func TestStreamBookOverPackets(t *testing.T) {
	var content []string
	for i := 0; i < 70000; i++ {
		content = append(content, fmt.Sprintf(`["palabra%d", "word %d / another longer word"]`, i, i))
	}
	dir := t.TempDir()
	writeStory(t, dir, "book.json", `{"title": "Libro", "content": [`+strings.Join(content, ",")+`]}`)
	app := newApp([]string{dir}, filepath.Join(t.TempDir(), "state.json"))

	sock := filepath.Join(t.TempDir(), "app.sock")
	ln, err := net.ListenUnix("unixpacket", &net.UnixAddr{Name: sock, Net: "unixpacket"})
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	accepted := make(chan *net.UnixConn)
	go func() {
		c, err := ln.AcceptUnix()
		if err != nil {
			t.Error(err)
		}
		accepted <- c
	}()
	client, err := appload.Dial(sock)
	if err != nil {
		t.Fatal(err)
	}
	server := <-accepted
	buf := make([]byte, appload.MaxMessageLength)
	roundTrip := func(msgType int32, body string) (int32, []byte) {
		for _, r := range app.handle(msgType, []byte(body)) {
			data, _ := json.Marshal(r.Body)
			if err := client.Send(r.Type, data); err != nil {
				t.Fatalf("send %d (%d bytes): %v", r.Type, len(data), err)
			}
		}
		n, _ := server.Read(buf)
		typ, length, _ := appload.DecodeHeader(buf[:n])
		n, _ = server.Read(buf[:length])
		return typ, append([]byte(nil), buf[:n]...)
	}

	if typ, body := roundTrip(reqOpen, `{"id": "book"}`); typ != respStory || len(body) > 4096 {
		t.Fatalf("open: %d, %d bytes", typ, len(body))
	}
	total, chunks := 0, 0
	for {
		typ, body := roundTrip(reqTokens, fmt.Sprintf(`{"id": "book", "from": %d}`, total))
		var c struct {
			From   int     `json:"from"`
			Tokens [][]any `json:"tokens"`
		}
		if err := json.Unmarshal(body, &c); err != nil || typ != respTokens || c.From != total {
			t.Fatalf("chunk at %d: type %d from %d %v", total, typ, c.From, err)
		}
		if len(c.Tokens) == 0 {
			break
		}
		total += len(c.Tokens)
		chunks++
	}
	if total != 70000 || chunks < 20 {
		t.Fatalf("%d tokens in %d chunks", total, chunks)
	}
}
