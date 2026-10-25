package main

import (
	"encoding/json"
	"fmt"
	"net"
	"path/filepath"
	"strings"
	"testing"
)

// Mirrors AppLoad: a SOCK_SEQPACKET listener that writes the header and the
// body as two separate packets.
func TestPacketTransport(t *testing.T) {
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
	client, err := dial(sock)
	if err != nil {
		t.Fatal(err)
	}
	server := <-accepted

	server.Write(encodeHeader(msgSystemNewCoordinator, 1))
	server.Write([]byte("1"))
	server.Write(encodeHeader(reqOpen, 11))
	server.Write([]byte(`{"id":"ab"}`))

	if typ, body, err := client.recv(); err != nil || typ != msgSystemNewCoordinator || string(body) != "1" {
		t.Fatalf("got %d %q %v", typ, body, err)
	}
	if typ, body, err := client.recv(); err != nil || typ != reqOpen || string(body) != `{"id":"ab"}` {
		t.Fatalf("got %d %q %v", typ, body, err)
	}

	big := make([]byte, 200000)
	for i := range big {
		big[i] = 'x'
	}
	if err := client.send(respStory, big); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, maxMessageLength)
	n, _ := server.Read(buf)
	typ, length, _ := decodeHeader(buf[:n])
	if n != 8 || typ != respStory || length != len(big) {
		t.Fatalf("header packet: n=%d type=%d len=%d", n, typ, length)
	}
	if n, _ = server.Read(buf); n != len(big) {
		t.Fatalf("body packet has %d bytes", n)
	}
	if err := client.send(1, nil); err == nil {
		t.Fatal("empty message should be refused")
	}
}

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
	client, err := dial(sock)
	if err != nil {
		t.Fatal(err)
	}
	server := <-accepted
	buf := make([]byte, maxMessageLength)
	roundTrip := func(msgType int32, body string) (int32, []byte) {
		for _, r := range app.handle(msgType, []byte(body)) {
			data, _ := json.Marshal(r.Body)
			if err := client.send(r.Type, data); err != nil {
				t.Fatalf("send %d (%d bytes): %v", r.Type, len(data), err)
			}
		}
		n, _ := server.Read(buf)
		typ, length, _ := decodeHeader(buf[:n])
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
